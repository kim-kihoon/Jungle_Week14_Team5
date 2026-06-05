local PISTOL_IDLE_PATH = "Content/Data/human/Pistol Idle_Armature_Pistol_Idle.uasset"
local PISTOL_WALK_PATH = "Content/Data/human/Pistol Walk_Armature_Pistol_Walk.uasset"

-- TODO: replace these with camera-specific hold animations after import.
local CAMERA_IDLE_PATH = PISTOL_IDLE_PATH
local CAMERA_WALK_PATH = PISTOL_WALK_PATH

-- TODO: replace these with equip/switch animations after import.
local PISTOL_TO_CAMERA_PATH = CAMERA_IDLE_PATH
local CAMERA_TO_PISTOL_PATH = PISTOL_IDLE_PATH

local FPS_SPEED_THRESHOLD = 0.5
local FPS_IDLE_TO_WALK_BLEND = 0.15
local FPS_WALK_TO_IDLE_BLEND = 0.15
local FPS_TOOL_SWITCH_BLEND = 0.2
local FPS_TOOL_SWITCH_DURATION = 0.35
local KEY_SPACE = 0x20
local PISTOL_SOCKET = "PistolSocket"
local CAMERA_SOCKET = "CameraSocket"
local TOOL_PISTOL = 0
local TOOL_CAMERA = 1

function init(self)
    self.Speed = 0.0
    self.SpeedThreshold = FPS_SPEED_THRESHOLD
    self.CurrentTool = TOOL_PISTOL
    self.SwitchTarget = TOOL_PISTOL
    self.SwitchTime = 0.0
    self.IsSwitchingTool = false

    local fps = Anim.create_state_machine("FPS")

    Anim.sm_add_state(fps, "PistolIdle", Anim.create_sequence_player(PISTOL_IDLE_PATH, 1.0, true))
    Anim.sm_add_state(fps, "PistolWalk", Anim.create_sequence_player(PISTOL_WALK_PATH, 1.0, true))
    Anim.sm_add_state(fps, "CameraIdle", Anim.create_sequence_player(CAMERA_IDLE_PATH, 1.0, true))
    Anim.sm_add_state(fps, "CameraWalk", Anim.create_sequence_player(CAMERA_WALK_PATH, 1.0, true))
    Anim.sm_add_state(fps, "SwitchToCamera", Anim.create_sequence_player(PISTOL_TO_CAMERA_PATH, 1.0, false))
    Anim.sm_add_state(fps, "SwitchToPistol", Anim.create_sequence_player(CAMERA_TO_PISTOL_PATH, 1.0, false))

    Anim.sm_add_transition(fps, "PistolIdle", "PistolWalk",
        function()
            return not self.IsSwitchingTool and self.CurrentTool == TOOL_PISTOL and self.Speed > self.SpeedThreshold
        end,
        FPS_IDLE_TO_WALK_BLEND)

    Anim.sm_add_transition(fps, "PistolWalk", "PistolIdle",
        function()
            return not self.IsSwitchingTool and self.CurrentTool == TOOL_PISTOL and self.Speed <= self.SpeedThreshold
        end,
        FPS_WALK_TO_IDLE_BLEND)

    Anim.sm_add_transition(fps, "CameraIdle", "CameraWalk",
        function()
            return not self.IsSwitchingTool and self.CurrentTool == TOOL_CAMERA and self.Speed > self.SpeedThreshold
        end,
        FPS_IDLE_TO_WALK_BLEND)

    Anim.sm_add_transition(fps, "CameraWalk", "CameraIdle",
        function()
            return not self.IsSwitchingTool and self.CurrentTool == TOOL_CAMERA and self.Speed <= self.SpeedThreshold
        end,
        FPS_WALK_TO_IDLE_BLEND)

    Anim.sm_add_transition(fps, "PistolIdle", "SwitchToCamera",
        function()
            return self.IsSwitchingTool and self.SwitchTarget == TOOL_CAMERA
        end,
        FPS_TOOL_SWITCH_BLEND)

    Anim.sm_add_transition(fps, "PistolWalk", "SwitchToCamera",
        function()
            return self.IsSwitchingTool and self.SwitchTarget == TOOL_CAMERA
        end,
        FPS_TOOL_SWITCH_BLEND)

    Anim.sm_add_transition(fps, "CameraIdle", "SwitchToPistol",
        function()
            return self.IsSwitchingTool and self.SwitchTarget == TOOL_PISTOL
        end,
        FPS_TOOL_SWITCH_BLEND)

    Anim.sm_add_transition(fps, "CameraWalk", "SwitchToPistol",
        function()
            return self.IsSwitchingTool and self.SwitchTarget == TOOL_PISTOL
        end,
        FPS_TOOL_SWITCH_BLEND)

    Anim.sm_add_transition(fps, "SwitchToCamera", "CameraIdle",
        function()
            return not self.IsSwitchingTool and self.CurrentTool == TOOL_CAMERA and self.Speed <= self.SpeedThreshold
        end,
        FPS_TOOL_SWITCH_BLEND)

    Anim.sm_add_transition(fps, "SwitchToCamera", "CameraWalk",
        function()
            return not self.IsSwitchingTool and self.CurrentTool == TOOL_CAMERA and self.Speed > self.SpeedThreshold
        end,
        FPS_TOOL_SWITCH_BLEND)

    Anim.sm_add_transition(fps, "SwitchToPistol", "PistolIdle",
        function()
            return not self.IsSwitchingTool and self.CurrentTool == TOOL_PISTOL and self.Speed <= self.SpeedThreshold
        end,
        FPS_TOOL_SWITCH_BLEND)

    Anim.sm_add_transition(fps, "SwitchToPistol", "PistolWalk",
        function()
            return not self.IsSwitchingTool and self.CurrentTool == TOOL_PISTOL and self.Speed > self.SpeedThreshold
        end,
        FPS_TOOL_SWITCH_BLEND)

    Anim.sm_set_initial_state(fps, "PistolIdle")
    Anim.set_root_node(fps)
    Anim.toggle_socket_children(PISTOL_SOCKET, CAMERA_SOCKET)
end

function update(self, dt)
    self.Speed = Anim.get_owner_speed()

    if self.IsSwitchingTool then
        self.SwitchTime = self.SwitchTime + dt
        if self.SwitchTime >= FPS_TOOL_SWITCH_DURATION then
            self.CurrentTool = self.SwitchTarget
            self.IsSwitchingTool = false

            if self.CurrentTool == TOOL_CAMERA then
                Anim.toggle_socket_children(CAMERA_SOCKET, PISTOL_SOCKET)
            else
                Anim.toggle_socket_children(PISTOL_SOCKET, CAMERA_SOCKET)
            end
        end
    elseif Anim.is_key_pressed(KEY_SPACE) then
        self.SwitchTime = 0.0
        self.IsSwitchingTool = true

        if self.CurrentTool == TOOL_CAMERA then
            self.SwitchTarget = TOOL_PISTOL
        else
            self.SwitchTarget = TOOL_CAMERA
        end
    end
end
