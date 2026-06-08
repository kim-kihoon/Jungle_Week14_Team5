local GameManager = require("GameManager")
local StageManager = require("StageManager")

local EndingManager = {}

EndingManager.bActive = false

EndingManager.ENDING_SPAWN_TAG = "EndingSpawn"
EndingManager.ENDING_SUN_NAME = "EndingSun"
EndingManager.ENDING_SUN_TAG = "EndingLighting"
EndingManager.ENDING_MAP_NAME = "EndingHospital"

EndingManager.FALLBACK_SPAWN = Vec3(600.0, 0.0, 38.0)

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

function EndingManager:Reset()
    self.bActive = false
    self:SetEndingLightingEnabled(false)
    self:SetHorrorLightingEnabled(true)
end

function EndingManager:Enter(player, hit)
    if self.bActive then
        return false
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

    self:SetHorrorLightingEnabled(false)
    self:SetEndingLightingEnabled(true)

    if GameManager._SetState ~= nil then
        GameManager:_SetState(GameManager.State.Ending, "FinalAnomalyShot")
    end

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
