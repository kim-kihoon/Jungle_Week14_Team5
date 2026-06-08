local LoopManager = {}

LoopManager.bLoopStopped = false
LoopManager.bCymbalMonkeyCycleStarted = false
LoopManager.bCymbalDoorTriggerUsed = false

function LoopManager:Reset()
    self.bLoopStopped = false
    self.bCymbalMonkeyCycleStarted = false
    self.bCymbalDoorTriggerUsed = false
end

function LoopManager:StartStopped()
    self.bLoopStopped = true
    self.bCymbalMonkeyCycleStarted = false
    self.bCymbalDoorTriggerUsed = false
end

function LoopManager:IsCymbalDoorTriggerUsed()
    return self.bCymbalDoorTriggerUsed == true
end

function LoopManager:IsLoopStopped()
    return self.bLoopStopped == true
end

function LoopManager:IsCymbalMonkeyCycleStarted()
    return self.bCymbalMonkeyCycleStarted == true
end

function LoopManager:StopLoop(gameManager, reason)
    if self.bLoopStopped then
        return false
    end

    self.bLoopStopped = true
    if self.bCymbalMonkeyCycleStarted then
        self.bCymbalMonkeyCycleStarted = false
        if gameManager ~= nil and gameManager._FireEvent ~= nil then
            gameManager:_FireEvent("CymbalMonkeyCycleReset", reason or "StopLoop")
        end
    end
    if gameManager ~= nil and gameManager._FireEvent ~= nil then
        gameManager:_FireEvent("LoopStopped", reason or "StopLoop")
    end
    return true
end

function LoopManager:ResetCymbalMonkeyCycle(gameManager, reason)
    local bWasStarted = self.bCymbalMonkeyCycleStarted == true
    self.bCymbalMonkeyCycleStarted = false

    if gameManager ~= nil and gameManager._FireEvent ~= nil then
        gameManager:_FireEvent("CymbalMonkeyCycleReset", reason or "ResetCymbalMonkeyCycle")
    end
    return bWasStarted
end

function LoopManager:StartCymbalMonkeyCycle(gameManager)
    if self.bCymbalDoorTriggerUsed then
        return false
    end
    if self.bCymbalMonkeyCycleStarted then
        return false
    end
    if gameManager == nil or gameManager.IsPlaying == nil or not gameManager:IsPlaying() then
        return false
    end
    if self.bLoopStopped then
        return false
    end

    self.bCymbalMonkeyCycleStarted = true
    self.bCymbalDoorTriggerUsed = true
    if gameManager._FireEvent ~= nil then
        gameManager:_FireEvent("CymbalMonkeyCycleStarted", "StartCymbalMonkeyCycle")
    end
    return true
end

function LoopManager:OnWarp(gameManager, reason, setupCallback)
    if gameManager == nil or gameManager.IsPlaying == nil or not gameManager:IsPlaying() then
        return false
    end

    reason = reason or "OnWarp"
    self.bCymbalDoorTriggerUsed = false
    self:ResetCymbalMonkeyCycle(gameManager, reason)

    if type(setupCallback) ~= "function" then
        return false
    end
    return setupCallback(reason) == true
end

function LoopManager:OnLoopStart(gameManager, reason, onStarted)
    if gameManager == nil or gameManager.IsPlaying == nil or not gameManager:IsPlaying() then
        return false
    end
    if not self.bLoopStopped then
        return false
    end

    reason = reason or "OnLoopStart"
    self.bLoopStopped = false

    if type(onStarted) == "function" then
        onStarted(reason)
    end

    if gameManager._FireEvent ~= nil then
        gameManager:_FireEvent("LoopRested", reason)
    end
    return true
end

return LoopManager
