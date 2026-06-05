local PISTOL_IDLE_PATH = "Content/Data/human/source/Armpist_Armature_FPS_Pistol_Idle.uasset"
local PISTOL_WALK_PATH = "Content/Data/human/source/Armpist_Armature_FPS_Pistol_Walk.uasset"
local PISTOL_FIRE_PATH = "Content/Data/human/source/Armpist_Armature_FPS_Pistol_Fire.uasset"
local CAMERA_MESH_PATH = "Content/Data/camera/camera_StaticMesh.uasset"

local FPS_SPEED_THRESHOLD = 0.5
local FPS_IDLE_TO_WALK_BLEND = 0.15
local FPS_WALK_TO_IDLE_BLEND = 0.15
local FPS_CAMERA_TO_PISTOL_BLEND = 0.15
local FPS_FIRE_ENTER_BLEND = 0.05
local FPS_FIRE_EXIT_BLEND = 0.1

local KEY_SPACE = 0x20
local PISTOL_SOCKET = "PistolSocket"

local TOOL_PISTOL = 0
local TOOL_CAMERA = 1

local SWITCH_NONE = 0
local SWITCH_TO_CAMERA = 1
local SWITCH_TO_PISTOL = 2

local ACTION_NONE = 0
local ACTION_PISTOL_FIRE = 1

local TOOL_SWITCH_DURATION = 0.35
local ARMS_READY_PITCH = 0.0
local ARMS_DOWN_PITCH = 65.0

-- Camera mesh is expected to be a child of CameraComponent.
-- X is forward from the camera, Z moves it between lower-screen hidden and raised positions.
local CAMERA_READY_X = 0.2
local CAMERA_READY_Y = 0.0
local CAMERA_READY_Z = 0.8
local CAMERA_DOWN_X = 0.5
local CAMERA_DOWN_Y = 0.0
local CAMERA_DOWN_Z = 0.0
local CAMERA_BOB_RATE = 7.5
local CAMERA_BOB_SMOOTH = 8.0
local CAMERA_BOB_FORWARD_AMOUNT = 0.010
local CAMERA_BOB_SIDE_AMOUNT = 0.010
local CAMERA_BOB_UP_AMOUNT = 0.015

local function clamp01(value)
    if value < 0.0 then
        return 0.0
    elseif value > 1.0 then
        return 1.0
    end
    return value
end

local function smooth_step(value)
    value = clamp01(value)
    return value * value * (3.0 - 2.0 * value)
end

local function lerp(a, b, alpha)
    return a + (b - a) * alpha
end

local function is_pistol(self)
    return self.CurrentTool == TOOL_PISTOL
end

local function is_idle(self)
    return self.Speed <= self.SpeedThreshold
end

local function is_walk(self)
    return self.Speed > self.SpeedThreshold
end

local function is_switching(self)
    return self.SwitchPhase ~= SWITCH_NONE
end

local function set_camera_mesh_position(alpha, bob_x, bob_y, bob_z)
    bob_x = bob_x or 0.0
    bob_y = bob_y or 0.0
    bob_z = bob_z or 0.0

    Anim.set_static_mesh_relative_location_by_path(
        CAMERA_MESH_PATH,
        lerp(CAMERA_DOWN_X, CAMERA_READY_X, alpha) + bob_x,
        lerp(CAMERA_DOWN_Y, CAMERA_READY_Y, alpha) + bob_y,
        lerp(CAMERA_DOWN_Z, CAMERA_READY_Z, alpha) + bob_z)
end

local function update_camera_hold_motion(self, dt)
    local targetWeight = 0.0
    if self.Speed > self.SpeedThreshold then
        targetWeight = clamp01((self.Speed - self.SpeedThreshold) / 4.0)
    end

    self.CameraBobWeight = lerp(self.CameraBobWeight, targetWeight, clamp01(dt * CAMERA_BOB_SMOOTH))
    self.CameraBobTime = self.CameraBobTime + dt * CAMERA_BOB_RATE * lerp(0.45, 1.0, self.CameraBobWeight)

    local phase = self.CameraBobTime
    local weight = self.CameraBobWeight
    local bobX = math.sin(phase * 2.0) * CAMERA_BOB_FORWARD_AMOUNT * weight
    local bobY = math.sin(phase) * CAMERA_BOB_SIDE_AMOUNT * weight
    local bobZ = math.abs(math.sin(phase)) * CAMERA_BOB_UP_AMOUNT * weight

    set_camera_mesh_position(1.0, bobX, bobY, bobZ)
end

local function show_pistol()
    Anim.set_owner_mesh_pitch(ARMS_READY_PITCH)
    Anim.set_owner_mesh_visibility(true)
    Anim.set_socket_child_visibility(PISTOL_SOCKET, true)
    Anim.set_static_mesh_visibility_by_path(CAMERA_MESH_PATH, false)
    set_camera_mesh_position(0.0)
end

local function show_camera()
    Anim.set_owner_mesh_pitch(ARMS_DOWN_PITCH)
    Anim.set_owner_mesh_visibility(false)
    Anim.set_socket_child_visibility(PISTOL_SOCKET, false)
    Anim.set_static_mesh_visibility_by_path(CAMERA_MESH_PATH, true)
    set_camera_mesh_position(1.0)
end

local function update_switch_to_camera(self, alpha)
    alpha = smooth_step(alpha)
    Anim.set_owner_mesh_visibility(true)
    Anim.set_socket_child_visibility(PISTOL_SOCKET, true)
    Anim.set_static_mesh_visibility_by_path(CAMERA_MESH_PATH, true)
    Anim.set_owner_mesh_pitch(lerp(ARMS_READY_PITCH, ARMS_DOWN_PITCH, alpha))
    set_camera_mesh_position(alpha)
end

local function update_switch_to_pistol(self, alpha)
    alpha = smooth_step(alpha)
    Anim.set_owner_mesh_visibility(true)
    Anim.set_socket_child_visibility(PISTOL_SOCKET, true)
    Anim.set_static_mesh_visibility_by_path(CAMERA_MESH_PATH, true)
    Anim.set_owner_mesh_pitch(lerp(ARMS_DOWN_PITCH, ARMS_READY_PITCH, alpha))
    set_camera_mesh_position(1.0 - alpha)
end

function init(self)
    self.Speed = 0.0
    self.SpeedThreshold = FPS_SPEED_THRESHOLD
    self.CurrentTool = TOOL_PISTOL
    self.SwitchPhase = SWITCH_NONE
    self.SwitchTime = 0.0
    self.ActionPhase = ACTION_NONE
    self.ActionTime = 0.0
    self.CameraBobTime = 0.0
    self.CameraBobWeight = 0.0
    self.PistolFireDuration = Anim.get_sequence_length(PISTOL_FIRE_PATH)

    local fps = Anim.create_state_machine("FPS")

    Anim.sm_add_state(fps, "PistolIdle", Anim.create_sequence_player(PISTOL_IDLE_PATH, 1.0, true))
    Anim.sm_add_state(fps, "PistolWalk", Anim.create_sequence_player(PISTOL_WALK_PATH, 1.0, true))
    Anim.sm_add_state(fps, "PistolFire", Anim.create_sequence_player(PISTOL_FIRE_PATH, 1.0, false))
    Anim.sm_add_state(fps, "CameraHold", Anim.create_ref_pose())

    Anim.sm_add_transition(fps, "PistolIdle", "PistolWalk",
        function()
            return not is_switching(self) and self.ActionPhase == ACTION_NONE and is_pistol(self) and is_walk(self)
        end,
        FPS_IDLE_TO_WALK_BLEND)

    Anim.sm_add_transition(fps, "PistolWalk", "PistolIdle",
        function()
            return not is_switching(self) and self.ActionPhase == ACTION_NONE and is_pistol(self) and is_idle(self)
        end,
        FPS_WALK_TO_IDLE_BLEND)

    Anim.sm_add_transition(fps, "PistolIdle", "PistolFire",
        function()
            return self.ActionPhase == ACTION_PISTOL_FIRE
        end,
        FPS_FIRE_ENTER_BLEND)

    Anim.sm_add_transition(fps, "PistolWalk", "PistolFire",
        function()
            return self.ActionPhase == ACTION_PISTOL_FIRE
        end,
        FPS_FIRE_ENTER_BLEND)

    Anim.sm_add_transition(fps, "PistolFire", "PistolIdle",
        function()
            return self.ActionPhase == ACTION_NONE and is_pistol(self) and is_idle(self)
        end,
        FPS_FIRE_EXIT_BLEND)

    Anim.sm_add_transition(fps, "PistolFire", "PistolWalk",
        function()
            return self.ActionPhase == ACTION_NONE and is_pistol(self) and is_walk(self)
        end,
        FPS_FIRE_EXIT_BLEND)

    Anim.sm_add_transition(fps, "PistolIdle", "CameraHold",
        function()
            return self.SwitchPhase == SWITCH_NONE and self.CurrentTool == TOOL_CAMERA
        end,
        0.0)

    Anim.sm_add_transition(fps, "PistolWalk", "CameraHold",
        function()
            return self.SwitchPhase == SWITCH_NONE and self.CurrentTool == TOOL_CAMERA
        end,
        0.0)

    Anim.sm_add_transition(fps, "CameraHold", "PistolIdle",
        function()
            return self.SwitchPhase == SWITCH_NONE and is_pistol(self) and is_idle(self)
        end,
        FPS_CAMERA_TO_PISTOL_BLEND)

    Anim.sm_add_transition(fps, "CameraHold", "PistolWalk",
        function()
            return self.SwitchPhase == SWITCH_NONE and is_pistol(self) and is_walk(self)
        end,
        FPS_CAMERA_TO_PISTOL_BLEND)

    Anim.sm_set_initial_state(fps, "PistolIdle")
    Anim.set_root_node(fps)
    show_pistol()
end

function update(self, dt)
    self.Speed = Anim.get_owner_speed()

    if self.ActionPhase == ACTION_PISTOL_FIRE then
        self.ActionTime = self.ActionTime + dt
        if self.ActionTime >= self.PistolFireDuration then
            self.ActionTime = 0.0
            self.ActionPhase = ACTION_NONE
        end
        return
    end

    if self.SwitchPhase == SWITCH_NONE then
        if Anim.is_key_pressed(KEY_SPACE) then
            self.SwitchTime = 0.0
            if self.CurrentTool == TOOL_PISTOL then
                self.SwitchPhase = SWITCH_TO_CAMERA
                update_switch_to_camera(self, 0.0)
            else
                self.SwitchPhase = SWITCH_TO_PISTOL
                update_switch_to_pistol(self, 0.0)
            end
        elseif self.CurrentTool == TOOL_PISTOL and Anim.is_left_mouse_pressed() then
            self.ActionTime = 0.0
            self.ActionPhase = ACTION_PISTOL_FIRE
        elseif self.CurrentTool == TOOL_CAMERA then
            update_camera_hold_motion(self, dt)
        end
        return
    end

    self.SwitchTime = self.SwitchTime + dt
    local alpha = clamp01(self.SwitchTime / TOOL_SWITCH_DURATION)

    if self.SwitchPhase == SWITCH_TO_CAMERA then
        update_switch_to_camera(self, alpha)
        if alpha >= 1.0 then
            self.SwitchTime = 0.0
            self.SwitchPhase = SWITCH_NONE
            self.CurrentTool = TOOL_CAMERA
            show_camera()
        end
    elseif self.SwitchPhase == SWITCH_TO_PISTOL then
        update_switch_to_pistol(self, alpha)
        if alpha >= 1.0 then
            self.SwitchTime = 0.0
            self.SwitchPhase = SWITCH_NONE
            self.CurrentTool = TOOL_PISTOL
            show_pistol()
        end
    end
end
