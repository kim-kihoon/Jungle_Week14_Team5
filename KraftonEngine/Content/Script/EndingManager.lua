local GameManager = require("GameManager")
local StageManager = require("StageManager")
local UIManager = require("UIManager")

local EndingManager = {}

EndingManager.bActive = false

EndingManager.ENDING_SPAWN_TAG = "EndingSpawn"
EndingManager.ENDING_SUN_NAME = "EndingSun"
EndingManager.ENDING_SUN_TAG = "EndingLighting"
EndingManager.ENDING_MAP_NAME = "EndingHospital"

EndingManager.FALLBACK_SPAWN = Vec3(600.0, 0.0, 38.0)
EndingManager.ENDING_SPAWN_YAW = -180.0
EndingManager.ENDING_SPAWN_PITCH = 15.0
EndingManager.WAKE_UP_SHOT_TRACE_DISTANCE = 1000.0

EndingManager.VICTIM_ACTOR_TEMPLATE = "Content/Blueprint/ending/EndingVictim.ActorTemplate"
EndingManager.VICTIM_LOCATION = Vec3(597.0, 0.0, 0.0)
EndingManager.VICTIM_ROTATION = Vec3(0.0, 0.0, 0.0)
EndingManager.VICTIM_SCALE = Vec3(0.35, 0.35, 0.35)
EndingManager.VICTIM_ANIMATION_PATH =
    "Content/Data/ending-hospital-map-data/victim-with-animation_Object_4_C4D_Animation_Take.uasset"
EndingManager.VICTIM_ANIMATION_LOOPING = false
EndingManager.VICTIM_ANIMATION_PLAY_RATE = 1.0

EndingManager.VictimActor = nil

EndingManager.HORROR_LIGHT_CLASSES = {
    "AAmbientLightActor",
    "ASpotLightActor",
    "APointLightActor",
}

local function is_valid_actor(actor)
    if actor == nil then
        return false
    end
    if actor.IsValid == nil then
        return true
    end
    return actor:IsValid()
end

local function find_actor_by_name(name)
    if World == nil or World.FindActorByName == nil or name == nil then
        return nil
    end
    local ok, actor = pcall(function()
        return World.FindActorByName(name)
    end)
    if ok and is_valid_actor(actor) then
        return actor
    end
    return nil
end

local function find_first_actor_by_tag(tag)
    if World == nil or World.FindFirstActorByTag == nil or tag == nil then
        return nil
    end
    local ok, actor = pcall(function()
        return World.FindFirstActorByTag(tag)
    end)
    if ok and is_valid_actor(actor) then
        return actor
    end
    return nil
end

local function get_player_pawn()
    if World == nil or World.GetFirstPlayerController == nil then
        return nil
    end

    local controller = World.GetFirstPlayerController()
    if controller == nil or controller.GetPossessedPawn == nil then
        return nil
    end
    return controller:GetPossessedPawn()
end

local function get_pawn_from_player(player)
    if player == nil then
        return get_player_pawn()
    end

    if player.AsPawn ~= nil then
        local ok, pawn = pcall(function()
            return player:AsPawn()
        end)
        if ok and pawn ~= nil then
            return pawn
        end
    end

    if player.SetControlRotation ~= nil then
        return player
    end

    return get_player_pawn()
end

local function apply_ending_spawn_facing(player)
    local pawn = get_pawn_from_player(player)
    local currentRotation = Vec3(0.0, 0.0, 0.0)

    if pawn ~= nil and pawn.GetControlRotation ~= nil then
        local ok, rotation = pcall(function()
            return pawn:GetControlRotation()
        end)
        if ok and rotation ~= nil then
            currentRotation = Vec3(rotation.X or 0.0, rotation.Y or 0.0, rotation.Z or 0.0)
        end
    elseif player ~= nil then
        local ok, rotation = pcall(function()
            return player.Rotation
        end)
        if ok and rotation ~= nil then
            currentRotation = Vec3(rotation.X or 0.0, rotation.Y or 0.0, rotation.Z or 0.0)
        end
    end

    -- FVector(Roll, Pitch, Yaw): yaw=-X, pitch=아래 15도(+Pitch), roll은 유지.
    local targetRotation = Vec3(
        currentRotation.X,
        EndingManager.ENDING_SPAWN_PITCH,
        EndingManager.ENDING_SPAWN_YAW
    )

    if pawn ~= nil and pawn.SetControlRotation ~= nil then
        pcall(function()
            pawn:SetControlRotation(targetRotation)
        end)
    end

    if player ~= nil and player.SetRotation ~= nil then
        pcall(function()
            player:SetRotation(targetRotation)
        end)
    end
end

local function find_actors_by_class(className)
    if World == nil or World.FindActorsByClass == nil or className == nil then
        return {}
    end
    local ok, actors = pcall(function()
        return World.FindActorsByClass(className)
    end)
    if ok and type(actors) == "table" then
        return actors
    end
    return {}
end

local function set_component_light_visible(component, bVisible)
    if component == nil then
        return
    end
    pcall(function()
        if component.SetVisible ~= nil then
            component:SetVisible(bVisible)
        end
    end)
    pcall(function()
        if component.PushToScene ~= nil then
            component:PushToScene()
        end
    end)
end

local function set_actor_lights_visible(actor, bVisible)
    if not is_valid_actor(actor) then
        return
    end

    pcall(function()
        actor:SetVisible(bVisible)
    end)

    local ok, components = pcall(function()
        return actor:GetComponents()
    end)
    if ok and type(components) == "table" then
        for _, component in ipairs(components) do
            set_component_light_visible(component, bVisible)
        end
    end
end

local function is_ending_sun_actor(actor)
    if not is_valid_actor(actor) then
        return false
    end
    if actor.GetName ~= nil then
        local ok, name = pcall(function()
            return actor:GetName()
        end)
        if ok and name == EndingManager.ENDING_SUN_NAME then
            return true
        end
    end
    if actor.HasTag ~= nil and actor:HasTag(EndingManager.ENDING_SUN_TAG) then
        return true
    end
    return false
end

function EndingManager:IsActive()
    return self.bActive == true
end

function EndingManager:SetHorrorLightingEnabled(bEnabled)
    for _, className in ipairs(self.HORROR_LIGHT_CLASSES) do
        for _, actor in ipairs(find_actors_by_class(className)) do
            set_actor_lights_visible(actor, bEnabled)
        end
    end

    for _, actor in ipairs(find_actors_by_class("ADirectionalLightActor")) do
        if not is_ending_sun_actor(actor) then
            set_actor_lights_visible(actor, bEnabled)
        end
    end
end

function EndingManager:SetEndingLightingEnabled(bEnabled)
    local endingSun = find_actor_by_name(self.ENDING_SUN_NAME)
        or find_first_actor_by_tag(self.ENDING_SUN_TAG)
    if endingSun ~= nil then
        set_actor_lights_visible(endingSun, bEnabled)
    end
end

function EndingManager:GetSpawnLocation()
    local spawnActor = find_first_actor_by_tag(self.ENDING_SPAWN_TAG)
        or find_actor_by_name("EndingSpawn")
    if spawnActor ~= nil and spawnActor.GetLocation ~= nil then
        local ok, location = pcall(function()
            return spawnActor:GetLocation()
        end)
        if ok and location ~= nil then
            return Vec3(location.X or 0.0, location.Y or 0.0, location.Z or 0.0)
        end
    end
    return self.FALLBACK_SPAWN
end

function EndingManager:Initialize()
    self.bActive = false
    self:SetEndingLightingEnabled(false)
end

local function destroy_ending_victim_actor(actor)
    if not is_valid_actor(actor) or actor.Destroy == nil then
        return
    end
    pcall(function()
        actor:Destroy()
    end)
end

local function get_skeletal_mesh_from_actor(actor)
    if not is_valid_actor(actor) or actor.GetSkeletalMeshComponent == nil then
        return nil
    end
    local ok, mesh = pcall(function()
        return actor:GetSkeletalMeshComponent()
    end)
    if ok then
        return mesh
    end
    return nil
end

function EndingManager:DespawnVictim()
    destroy_ending_victim_actor(self.VictimActor)
    self.VictimActor = nil
end

function EndingManager:SpawnVictim()
    self:DespawnVictim()

    if World == nil or World.SpawnActorTemplate == nil then
        print("[EndingManager] SpawnVictim failed: World.SpawnActorTemplate unavailable")
        return false
    end

    local ok, actor = pcall(function()
        return World.SpawnActorTemplate(
            self.VICTIM_ACTOR_TEMPLATE,
            self.VICTIM_LOCATION,
            self.VICTIM_ROTATION,
            self.VICTIM_SCALE
        )
    end)
    if not ok or not is_valid_actor(actor) then
        print("[EndingManager] SpawnVictim failed: actor template spawn error")
        return false
    end

    self.VictimActor = actor

    local mesh = get_skeletal_mesh_from_actor(actor)
    if mesh == nil or mesh.PlayAnimationByPath == nil then
        print("[EndingManager] SpawnVictim failed: skeletal mesh component unavailable")
        return false
    end

    local playOk, playResult = pcall(function()
        return mesh:PlayAnimationByPath(self.VICTIM_ANIMATION_PATH, self.VICTIM_ANIMATION_LOOPING)
    end)
    if not playOk or playResult == false then
        print("[EndingManager] SpawnVictim failed: PlayAnimationByPath returned false")
        return false
    end

    if mesh.SetPlayRate ~= nil then
        pcall(function()
            mesh:SetPlayRate(self.VICTIM_ANIMATION_PLAY_RATE)
        end)
    end

    print(string.format(
        "[EndingManager] Victim spawned at (%.2f, %.2f, %.2f) anim=%s",
        self.VICTIM_LOCATION.X,
        self.VICTIM_LOCATION.Y,
        self.VICTIM_LOCATION.Z,
        self.VICTIM_ANIMATION_PATH
    ))
    return true
end

function EndingManager:Reset()
    self.bActive = false
    self:DespawnVictim()
    UIManager:ExitCutsceneMode()
    self:SetEndingLightingEnabled(false)
    self:SetHorrorLightingEnabled(true)
end

local function play_wake_up_pistol_audio()
    if Audio == nil or Audio.Play == nil then
        return
    end

    pcall(function()
        Audio.Play("PistolFire", 1.0)
    end)
end

local function get_wake_up_shot_hit(player)
    if player == nil or player.GetCamera == nil or World == nil or World.LineTraceObjects == nil then
        return nil
    end

    local camera = player:GetCamera()
    if camera == nil or camera.GetLocation == nil then
        return nil
    end

    local okStart, start = pcall(function()
        return camera:GetLocation()
    end)
    if not okStart or start == nil then
        return nil
    end

    local direction = camera.Forward
    if direction == nil then
        return nil
    end

    local target = start + direction * EndingManager.WAKE_UP_SHOT_TRACE_DISTANCE
    local okHit, traceHit = pcall(function()
        return World.LineTraceObjects(start, target, player)
    end)
    if okHit and traceHit ~= nil and traceHit.Hit then
        return traceHit
    end

    return nil
end

function EndingManager:PlayWakeUpShot(player)
    if player == nil then
        player = get_player_pawn()
    end
    if player == nil then
        return false
    end

    if HospitalPlayer ~= nil and HospitalPlayer.play_pistol_fire_effect ~= nil then
        pcall(function()
            HospitalPlayer.play_pistol_fire_effect(player)
        end)
    end

    play_wake_up_pistol_audio()

    local endingHit = get_wake_up_shot_hit(player)
    if endingHit ~= nil and GameManager._PlayAnomalyHitEffect ~= nil then
        GameManager:_PlayAnomalyHitEffect(player, endingHit)
    end

    return true
end

function EndingManager:Enter(player, hit)
    if self.bActive then
        return false
    end
    if player == nil then
        player = get_player_pawn()
    end
    if player == nil or player.SetLocation == nil then
        print("[EndingManager] Enter failed: player unavailable")
        return false
    end

    self.bActive = true

    GameManager:ClearActiveAnomalyOutline()
    require("AnomalyManager"):DespawnCurrent("EndingEnter")
    GameManager:_ClearAnomalyPlacement()
    require("JumpScareManager"):DeactivateAll()
    require("DoorManager"):ClearToyProjectiles()

    local spawnLocation = self:GetSpawnLocation()
    pcall(function()
        player:SetLocation(spawnLocation)
    end)
    apply_ending_spawn_facing(player)
    UIManager:EnterCutsceneMode()

    self:SetHorrorLightingEnabled(false)
    self:SetEndingLightingEnabled(true)
    self:SpawnVictim()

    if GameManager._SetState ~= nil then
        GameManager:_SetState(GameManager.State.Ending, "FinalAnomalyShot")
    end

    self:PlayWakeUpShot(player)

    print(string.format(
        "[EndingManager] Entered ending at (%.2f, %.2f, %.2f) stage=%d",
        spawnLocation.X,
        spawnLocation.Y,
        spawnLocation.Z,
        StageManager:GetStage()
    ))
    return true
end

return EndingManager
