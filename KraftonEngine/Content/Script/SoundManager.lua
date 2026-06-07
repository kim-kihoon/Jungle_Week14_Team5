local SoundManager = {}

SoundManager.DoorOpenSoundKey = "DoorOpen"
SoundManager.HeavyDoorOpenSoundKey = "HeavyDoorOpen"
SoundManager.DoorCloseSoundKey = "DoorClose"
SoundManager.DoorSoundMinDistance = 1.0
SoundManager.DoorSoundMaxDistance = 12.0
SoundManager.DoorSoundVolume = 0.45
SoundManager.DoorOpenSoundVolume = 0.7
SoundManager.DoorCloseSoundDelay = 1.0
SoundManager.PartyBlowerSoundKey = "PartyBlower"
SoundManager.PartyBlowerSoundVolume = 0.25
SoundManager.PendingDoorCloseSounds = {}

local function get_actor_location(actor)
    if actor == nil or actor.GetLocation == nil then
        return nil
    end

    local ok, location = pcall(function()
        return actor:GetLocation()
    end)
    if ok then
        return location
    end
    return nil
end

function SoundManager:Play(key, volume)
    if Audio == nil or Audio.Play == nil or key == nil then
        return false
    end

    local ok = pcall(function()
        Audio.Play(key, tonumber(volume) or 1.0)
    end)
    return ok == true
end

function SoundManager:PlayAt(key, volume, location, minDistance, maxDistance)
    if Audio == nil or key == nil or location == nil then
        return false
    end

    if Audio.PlayAt ~= nil then
        local ok = pcall(function()
            Audio.PlayAt(
                key,
                tonumber(volume) or 1.0,
                location,
                tonumber(minDistance) or self.DoorSoundMinDistance,
                tonumber(maxDistance) or self.DoorSoundMaxDistance
            )
        end)
        if ok then
            return true
        end
    end

    return self:Play(key, volume)
end

function SoundManager:PlayAtActor(actor, key, volume, minDistance, maxDistance)
    local location = get_actor_location(actor)
    if location == nil then
        return false
    end

    return self:PlayAt(key, volume, location, minDistance, maxDistance)
end

function SoundManager:PlayDoorOpen(actor, bHeavy)
    local key = bHeavy and self.HeavyDoorOpenSoundKey or self.DoorOpenSoundKey
    local volume = bHeavy and self.DoorSoundVolume or self.DoorOpenSoundVolume
    return self:PlayAtActor(actor, key, volume, self.DoorSoundMinDistance, self.DoorSoundMaxDistance)
end

function SoundManager:QueueDoorClose(actor)
    if actor == nil then
        return false
    end

    table.insert(self.PendingDoorCloseSounds, {
        Delay = self.DoorCloseSoundDelay,
        Actor = actor
    })
    return true
end

function SoundManager:Tick(dt)
    local deltaTime = tonumber(dt) or 0.0
    if deltaTime <= 0.0 then
        return
    end

    local index = 1
    while index <= #self.PendingDoorCloseSounds do
        local pending = self.PendingDoorCloseSounds[index]
        pending.Delay = pending.Delay - deltaTime
        if pending.Delay <= 0.0 then
            self:PlayAtActor(
                pending.Actor,
                self.DoorCloseSoundKey,
                self.DoorSoundVolume,
                self.DoorSoundMinDistance,
                self.DoorSoundMaxDistance
            )
            table.remove(self.PendingDoorCloseSounds, index)
        else
            index = index + 1
        end
    end
end

function SoundManager:Reset()
    self.PendingDoorCloseSounds = {}
end

function SoundManager:PlayPartyBlower()
    return self:Play(self.PartyBlowerSoundKey, self.PartyBlowerSoundVolume)
end

return SoundManager
