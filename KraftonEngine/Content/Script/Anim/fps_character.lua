local FPS_IDLE_PATH = "Content/Data/human/Pistol Idle_Armature_mixamo_com.uasset"
local FPS_WALK_PATH = "Content/Data/human/Pistol Walk_Armature_Pistol_Walk.uasset"

local FPS_SPEED_THRESHOLD = 0.5
local FPS_IDLE_TO_WALK_BLEND = 0.15
local FPS_WALK_TO_IDLE_BLEND = 0.15

function init(self)
    self.Speed = 0.0
    self.SpeedThreshold = FPS_SPEED_THRESHOLD

    local fps = Anim.create_state_machine("FPS")

    Anim.sm_add_state(fps, "Idle", Anim.create_sequence_player(FPS_IDLE_PATH, 1.0, true))
    Anim.sm_add_state(fps, "Walk", Anim.create_sequence_player(FPS_WALK_PATH, 1.0, true))

    Anim.sm_add_transition(fps, "Idle", "Walk",
        function()
            return self.Speed > self.SpeedThreshold
        end,
        FPS_IDLE_TO_WALK_BLEND)

    Anim.sm_add_transition(fps, "Walk", "Idle",
        function()
            return self.Speed <= self.SpeedThreshold
        end,
        FPS_WALK_TO_IDLE_BLEND)

    Anim.sm_set_initial_state(fps, "Idle")
    Anim.set_root_node(fps)
end

function update(self, dt)
    self.Speed = Anim.get_owner_speed()
end
