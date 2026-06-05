local PISTOL_IDLE_PATH = "Content/Data/human/source/Armpist_Armature_FPS_Pistol_Idle.uasset"
local PISTOL_WALK_PATH = "Content/Data/human/source/Armpist_Armature_FPS_Pistol_Walk.uasset"
local PISTOL_OUT_PATH = "Content/Data/human/Pistol Out_Armature_Pistol_Out.uasset"
local PISTOL_FIRE_PATH = "Content/Data/human/source/Armpist_Armature_FPS_Pistol_Fire.uasset"
local CAMERA_MESH_PATH = "Content/Data/camera/camera_StaticMesh.uasset"

local FPS_SPEED_THRESHOLD = 0.5
local FPS_IDLE_TO_WALK_BLEND = 0.15
local FPS_WALK_TO_IDLE_BLEND = 0.15
local FPS_TOOL_SWITCH_ENTER_BLEND = 0.15
local FPS_TOOL_SWITCH_CHAIN_BLEND = 0.0
local FPS_TOOL_SWITCH_EXIT_BLEND = 0.15
local FPS_FIRE_ENTER_BLEND = 0.05
local FPS_FIRE_EXIT_BLEND = 0.1
local KEY_SPACE = 0x20
local PISTOL_SOCKET = "PistolSocket"

local TOOL_PISTOL = 0
local TOOL_CAMERA = 1

local SWITCH_NONE = 0
local SWITCH_PISTOL_OUT = 1
local SWITCH_PISTOL_IN = 2

local ACTION_NONE = 0
local ACTION_PISTOL_FIRE = 1

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

local function show_pistol()
    Anim.set_owner_mesh_visibility(true)
    Anim.set_socket_child_visibility(PISTOL_SOCKET, true)
    Anim.set_static_mesh_visibility_by_path(CAMERA_MESH_PATH, false)
end

local function show_camera()
    Anim.set_owner_mesh_visibility(false)
    Anim.set_socket_child_visibility(PISTOL_SOCKET, false)
    Anim.set_static_mesh_visibility_by_path(CAMERA_MESH_PATH, true)
end

function init(self)
    self.Speed = 0.0
    self.SpeedThreshold = FPS_SPEED_THRESHOLD
    self.CurrentTool = TOOL_PISTOL
    self.SwitchPhase = SWITCH_NONE
    self.SwitchTime = 0.0
    self.ActionPhase = ACTION_NONE
    self.ActionTime = 0.0
    self.PistolOutDuration = Anim.get_sequence_length(PISTOL_OUT_PATH)
    self.PistolFireDuration = Anim.get_sequence_length(PISTOL_FIRE_PATH)

    local fps = Anim.create_state_machine("FPS")

    Anim.sm_add_state(fps, "PistolIdle", Anim.create_sequence_player(PISTOL_IDLE_PATH, 1.0, true))
    Anim.sm_add_state(fps, "PistolWalk", Anim.create_sequence_player(PISTOL_WALK_PATH, 1.0, true))
    Anim.sm_add_state(fps, "PistolOut", Anim.create_sequence_player(PISTOL_OUT_PATH, 1.0, false))
    Anim.sm_add_state(fps, "PistolIn", Anim.create_sequence_player(PISTOL_OUT_PATH, -1.0, false))
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

    Anim.sm_add_transition(fps, "PistolIdle", "PistolOut",
        function()
            return self.SwitchPhase == SWITCH_PISTOL_OUT
        end,
        FPS_TOOL_SWITCH_ENTER_BLEND)

    Anim.sm_add_transition(fps, "PistolWalk", "PistolOut",
        function()
            return self.SwitchPhase == SWITCH_PISTOL_OUT
        end,
        FPS_TOOL_SWITCH_ENTER_BLEND)

    Anim.sm_add_transition(fps, "PistolOut", "CameraHold",
        function()
            return self.SwitchPhase == SWITCH_NONE and self.CurrentTool == TOOL_CAMERA
        end,
        FPS_TOOL_SWITCH_CHAIN_BLEND)

    Anim.sm_add_transition(fps, "CameraHold", "PistolIn",
        function()
            return self.SwitchPhase == SWITCH_PISTOL_IN
        end,
        FPS_TOOL_SWITCH_CHAIN_BLEND)

    Anim.sm_add_transition(fps, "PistolIn", "PistolIdle",
        function()
            return self.SwitchPhase == SWITCH_NONE and is_pistol(self) and is_idle(self)
        end,
        FPS_TOOL_SWITCH_EXIT_BLEND)

    Anim.sm_add_transition(fps, "PistolIn", "PistolWalk",
        function()
            return self.SwitchPhase == SWITCH_NONE and is_pistol(self) and is_walk(self)
        end,
        FPS_TOOL_SWITCH_EXIT_BLEND)

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
                self.SwitchPhase = SWITCH_PISTOL_OUT
            else
                self.CurrentTool = TOOL_PISTOL
                self.SwitchPhase = SWITCH_PISTOL_IN
                show_pistol()
            end
        elseif self.CurrentTool == TOOL_PISTOL and Anim.is_left_mouse_pressed() then
            self.ActionTime = 0.0
            self.ActionPhase = ACTION_PISTOL_FIRE
        end
        return
    end

    self.SwitchTime = self.SwitchTime + dt

    if self.SwitchPhase == SWITCH_PISTOL_OUT and self.SwitchTime >= self.PistolOutDuration then
        self.SwitchTime = 0.0
        self.CurrentTool = TOOL_CAMERA
        self.SwitchPhase = SWITCH_NONE
        show_camera()
    elseif self.SwitchPhase == SWITCH_PISTOL_IN and self.SwitchTime >= self.PistolOutDuration then
        self.SwitchTime = 0.0
        self.SwitchPhase = SWITCH_NONE
    end
end
