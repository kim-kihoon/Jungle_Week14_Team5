local PISTOL_IDLE_PATH = "Content/Data/human/Pistol Idle_Armature_Pistol_Idle.uasset"
local PISTOL_WALK_PATH = "Content/Data/human/Pistol Walk_Armature_Pistol_Walk.uasset"
local PISTOL_OUT_PATH = "Content/Data/human/Pistol Out_Armature_Pistol_Out.uasset"

local CAMERA_IDLE_PATH = "Content/Data/human/Camera Idle_Armature_Camera_Idle.uasset"
local CAMERA_WALK_PATH = "Content/Data/human/Camera Walk_Armature_Camera_Walk.uasset"
local CAMERA_OUT_PATH = "Content/Data/human/Camera Out_Armature_Camera_Out.uasset"

local FPS_SPEED_THRESHOLD = 0.5
local FPS_IDLE_TO_WALK_BLEND = 0.15
local FPS_WALK_TO_IDLE_BLEND = 0.15
local FPS_TOOL_SWITCH_ENTER_BLEND = 0.15
local FPS_TOOL_SWITCH_CHAIN_BLEND = 0.0
local FPS_TOOL_SWITCH_EXIT_BLEND = 0.15
local KEY_SPACE = 0x20
local PISTOL_SOCKET = "PistolSocket"
local CAMERA_SOCKET = "CameraSocket"

local TOOL_PISTOL = 0
local TOOL_CAMERA = 1

local SWITCH_NONE = 0
local SWITCH_PISTOL_OUT = 1
local SWITCH_CAMERA_IN = 2
local SWITCH_CAMERA_OUT = 3
local SWITCH_PISTOL_IN = 4

local function is_pistol(self)
    return self.CurrentTool == TOOL_PISTOL
end

local function is_camera(self)
    return self.CurrentTool == TOOL_CAMERA
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

function init(self)
    self.Speed = 0.0
    self.SpeedThreshold = FPS_SPEED_THRESHOLD
    self.CurrentTool = TOOL_PISTOL
    self.SwitchPhase = SWITCH_NONE
    self.SwitchTime = 0.0
    self.PistolOutDuration = Anim.get_sequence_length(PISTOL_OUT_PATH)
    self.CameraOutDuration = Anim.get_sequence_length(CAMERA_OUT_PATH)

    local fps = Anim.create_state_machine("FPS")

    Anim.sm_add_state(fps, "PistolIdle", Anim.create_sequence_player(PISTOL_IDLE_PATH, 1.0, true))
    Anim.sm_add_state(fps, "PistolWalk", Anim.create_sequence_player(PISTOL_WALK_PATH, 1.0, true))
    Anim.sm_add_state(fps, "PistolOut", Anim.create_sequence_player(PISTOL_OUT_PATH, 1.0, false))
    Anim.sm_add_state(fps, "PistolIn", Anim.create_sequence_player(PISTOL_OUT_PATH, -1.0, false))

    Anim.sm_add_state(fps, "CameraIdle", Anim.create_sequence_player(CAMERA_IDLE_PATH, 1.0, true))
    Anim.sm_add_state(fps, "CameraWalk", Anim.create_sequence_player(CAMERA_WALK_PATH, 1.0, true))
    Anim.sm_add_state(fps, "CameraOut", Anim.create_sequence_player(CAMERA_OUT_PATH, 1.0, false))
    Anim.sm_add_state(fps, "CameraIn", Anim.create_sequence_player(CAMERA_OUT_PATH, -1.0, false))

    Anim.sm_add_transition(fps, "PistolIdle", "PistolWalk",
        function()
            return not is_switching(self) and is_pistol(self) and is_walk(self)
        end,
        FPS_IDLE_TO_WALK_BLEND)

    Anim.sm_add_transition(fps, "PistolWalk", "PistolIdle",
        function()
            return not is_switching(self) and is_pistol(self) and is_idle(self)
        end,
        FPS_WALK_TO_IDLE_BLEND)

    Anim.sm_add_transition(fps, "CameraIdle", "CameraWalk",
        function()
            return not is_switching(self) and is_camera(self) and is_walk(self)
        end,
        FPS_IDLE_TO_WALK_BLEND)

    Anim.sm_add_transition(fps, "CameraWalk", "CameraIdle",
        function()
            return not is_switching(self) and is_camera(self) and is_idle(self)
        end,
        FPS_WALK_TO_IDLE_BLEND)

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

    Anim.sm_add_transition(fps, "PistolOut", "CameraIn",
        function()
            return self.SwitchPhase == SWITCH_CAMERA_IN
        end,
        FPS_TOOL_SWITCH_CHAIN_BLEND)

    Anim.sm_add_transition(fps, "CameraIn", "CameraIdle",
        function()
            return self.SwitchPhase == SWITCH_NONE and is_camera(self) and is_idle(self)
        end,
        FPS_TOOL_SWITCH_EXIT_BLEND)

    Anim.sm_add_transition(fps, "CameraIn", "CameraWalk",
        function()
            return self.SwitchPhase == SWITCH_NONE and is_camera(self) and is_walk(self)
        end,
        FPS_TOOL_SWITCH_EXIT_BLEND)

    Anim.sm_add_transition(fps, "CameraIdle", "CameraOut",
        function()
            return self.SwitchPhase == SWITCH_CAMERA_OUT
        end,
        FPS_TOOL_SWITCH_ENTER_BLEND)

    Anim.sm_add_transition(fps, "CameraWalk", "CameraOut",
        function()
            return self.SwitchPhase == SWITCH_CAMERA_OUT
        end,
        FPS_TOOL_SWITCH_ENTER_BLEND)

    Anim.sm_add_transition(fps, "CameraOut", "PistolIn",
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
    Anim.toggle_socket_children(PISTOL_SOCKET, CAMERA_SOCKET)
end

function update(self, dt)
    self.Speed = Anim.get_owner_speed()

    if self.SwitchPhase == SWITCH_NONE then
        if Anim.is_key_pressed(KEY_SPACE) then
            self.SwitchTime = 0.0
            if self.CurrentTool == TOOL_PISTOL then
                self.SwitchPhase = SWITCH_PISTOL_OUT
            else
                self.SwitchPhase = SWITCH_CAMERA_OUT
            end
        end
        return
    end

    self.SwitchTime = self.SwitchTime + dt

    if self.SwitchPhase == SWITCH_PISTOL_OUT and self.SwitchTime >= self.PistolOutDuration then
        self.SwitchTime = 0.0
        self.CurrentTool = TOOL_CAMERA
        self.SwitchPhase = SWITCH_CAMERA_IN
        Anim.toggle_socket_children(CAMERA_SOCKET, PISTOL_SOCKET)
    elseif self.SwitchPhase == SWITCH_CAMERA_IN and self.SwitchTime >= self.CameraOutDuration then
        self.SwitchTime = 0.0
        self.SwitchPhase = SWITCH_NONE
    elseif self.SwitchPhase == SWITCH_CAMERA_OUT and self.SwitchTime >= self.CameraOutDuration then
        self.SwitchTime = 0.0
        self.CurrentTool = TOOL_PISTOL
        self.SwitchPhase = SWITCH_PISTOL_IN
        Anim.toggle_socket_children(PISTOL_SOCKET, CAMERA_SOCKET)
    elseif self.SwitchPhase == SWITCH_PISTOL_IN and self.SwitchTime >= self.PistolOutDuration then
        self.SwitchTime = 0.0
        self.SwitchPhase = SWITCH_NONE
    end
end
