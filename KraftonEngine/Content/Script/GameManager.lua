local GameManager = {}
local AnomalyManager = require("AnomalyManager")

GameManager.State = {
    Ready = "Ready",
    Playing = "Playing",
    Paused = "Paused",
    GameOver = "GameOver",
    Clear = "Clear"
}

GameManager.Pressure = {
    EntryStrike = 1,
    Warning = 2,
    FinalWarning = 3
}

GameManager.state = GameManager.State.Ready
GameManager.score = 0
GameManager.elapsedTime = 0
GameManager.remainingTime = 0
GameManager.timeLimit = nil
GameManager.isPlayerDead = false
GameManager.pressureStage = GameManager.Pressure.EntryStrike
GameManager.manualPressureStage = nil

GameManager._listeners = {
    StateChanged = {},
    ScoreChanged = {},
    PlayerDead = {},
    TimeExpired = {},
    PressureChanged = {}
}

local WARNING_REMAINING_RATIO = 0.1
local FINAL_WARNING_REMAINING_RATIO = 0.1

local function clamp_score(value)
    value = tonumber(value) or 0
    if value < 0 then
        return 0
    end
    return value
end

local function is_function(value)
    return type(value) == "function"
end

local function normalize_pressure(pressure)
    pressure = tonumber(pressure)
    if pressure == nil then
        return nil
    end

    pressure = math.floor(pressure)
    if pressure < GameManager.Pressure.EntryStrike or pressure > GameManager.Pressure.FinalWarning then
        return nil
    end

    return pressure
end

function GameManager:_GetRemainingRatio()
    local timeLimit = tonumber(self.timeLimit)
    if timeLimit == nil or timeLimit <= 0 then
        return 1.0
    end

    local remainingTime = tonumber(self.remainingTime) or timeLimit
    local ratio = remainingTime / timeLimit
    if ratio < 0.0 then
        return 0.0
    end
    if ratio > 1.0 then
        return 1.0
    end
    return ratio
end

function GameManager:_GetPressureStageFromTime()
    local remainingRatio = self:_GetRemainingRatio()

    if remainingRatio <= FINAL_WARNING_REMAINING_RATIO then
        return self.Pressure.FinalWarning
    end
    if remainingRatio <= WARNING_REMAINING_RATIO then
        return self.Pressure.Warning
    end
    return self.Pressure.EntryStrike
end

function GameManager:_ResolvePressureStage()
    local manualPressure = normalize_pressure(self.manualPressureStage)
    if manualPressure ~= nil then
        return manualPressure
    end
    return self:_GetPressureStageFromTime()
end

function GameManager:_FireEvent(eventName, ...)
    local listeners = self._listeners[eventName]
    if listeners == nil then
        return
    end

    for i = #listeners, 1, -1 do
        local callback = listeners[i]
        if is_function(callback) then
            local ok, err = pcall(callback, ...)
            if not ok then
                print("[GameManager] " .. eventName .. " callback error: " .. tostring(err))
            end
        else
            table.remove(listeners, i)
        end
    end
end

function GameManager:_SetState(nextState, reason)
    if self.state == nextState then
        return false
    end

    local previousState = self.state
    self.state = nextState
    self:_FireEvent("StateChanged", nextState, previousState, reason)
    return true
end

function GameManager:_SetPressureStage(nextStage, reason, forceNotify)
    nextStage = normalize_pressure(nextStage) or self.Pressure.EntryStrike

    local previousStage = self.pressureStage
    self.pressureStage = nextStage

    if forceNotify or previousStage ~= nextStage then
        self:_FireEvent("PressureChanged", nextStage, previousStage, reason)
        return true
    end

    return false
end

function GameManager:_RefreshPressureStage(reason, forceNotify)
    return self:_SetPressureStage(self:_ResolvePressureStage(), reason, forceNotify)
end

function GameManager:AddListener(eventName, callback)
    if not is_function(callback) then
        print("[GameManager] AddListener failed: callback must be a function")
        return nil
    end

    local listeners = self._listeners[eventName]
    if listeners == nil then
        print("[GameManager] AddListener failed: unknown event " .. tostring(eventName))
        return nil
    end

    table.insert(listeners, callback)
    return callback
end

function GameManager:RemoveListener(eventName, callback)
    local listeners = self._listeners[eventName]
    if listeners == nil or callback == nil then
        return false
    end

    for i = #listeners, 1, -1 do
        if listeners[i] == callback then
            table.remove(listeners, i)
            return true
        end
    end

    return false
end

function GameManager:OnStateChanged(callback)
    return self:AddListener("StateChanged", callback)
end

function GameManager:OnScoreChanged(callback)
    return self:AddListener("ScoreChanged", callback)
end

function GameManager:OnPlayerDead(callback)
    return self:AddListener("PlayerDead", callback)
end

function GameManager:OnTimeExpired(callback)
    return self:AddListener("TimeExpired", callback)
end

function GameManager:OnPressureChanged(callback)
    return self:AddListener("PressureChanged", callback)
end

function GameManager:Reset()
    AnomalyManager:Reset()
    self.score = 0
    self.elapsedTime = 0
    self.remainingTime = self.timeLimit or 0
    self.isPlayerDead = false
    self.manualPressureStage = nil
    self:_SetPressureStage(self.Pressure.EntryStrike, "Reset", false)
    self:_SetState(self.State.Ready, "Reset")
end

function GameManager:StartGame()
    self.elapsedTime = 0
    self.remainingTime = self.timeLimit or 0
    self.isPlayerDead = false
    self:_SetState(self.State.Playing, "StartGame")
    self:_RefreshPressureStage("StartGame", true)
end

function GameManager:PauseGame()
    if self.state ~= self.State.Playing then
        return false
    end

    return self:_SetState(self.State.Paused, "PauseGame")
end

function GameManager:ResumeGame()
    if self.state ~= self.State.Paused then
        return false
    end

    return self:_SetState(self.State.Playing, "ResumeGame")
end

function GameManager:GameOver(reason)
    if self.state == self.State.GameOver then
        return false
    end

    AnomalyManager:Reset()
    self:_SetPressureStage(self.Pressure.EntryStrike, reason or "GameOver", false)
    return self:_SetState(self.State.GameOver, reason or "GameOver")
end

function GameManager:ClearGame(reason)
    if self.state == self.State.Clear then
        return false
    end

    AnomalyManager:Reset()
    self:_SetPressureStage(self.Pressure.EntryStrike, reason or "ClearGame", false)
    return self:_SetState(self.State.Clear, reason or "ClearGame")
end

function GameManager:RestartGame()
    self:Reset()
    self:StartGame()
end

function GameManager:Tick(dt)
    if self.state ~= self.State.Playing then
        return
    end

    dt = tonumber(dt) or 0
    if dt < 0 then
        dt = 0
    end

    AnomalyManager:Tick(dt)
    self.elapsedTime = self.elapsedTime + dt

    if self.timeLimit ~= nil then
        self.remainingTime = self.remainingTime - dt
        if self.remainingTime <= 0 then
            self.remainingTime = 0
            self:_RefreshPressureStage("Tick", false)
            self:_FireEvent("TimeExpired")
            self:GameOver("TimeUp")
            return
        end
    end

    self:_RefreshPressureStage("Tick", false)
end

function GameManager:AddScore(amount)
    amount = tonumber(amount) or 0
    return self:SetScore(self.score + amount)
end

function GameManager:SetScore(value)
    local previousScore = self.score
    self.score = clamp_score(value)

    if previousScore ~= self.score then
        self:_FireEvent("ScoreChanged", self.score, previousScore)
    end

    return self.score
end

function GameManager:GetScore()
    return self.score
end

function GameManager:SetTimeLimit(seconds)
    seconds = tonumber(seconds)
    if seconds == nil or seconds <= 0 then
        self:ClearTimeLimit()
        return
    end

    self.timeLimit = seconds
    self.remainingTime = seconds
    if self.state == self.State.Playing then
        self:_RefreshPressureStage("SetTimeLimit", false)
    end
end

function GameManager:ClearTimeLimit()
    self.timeLimit = nil
    self.remainingTime = 0
    if self.state == self.State.Playing then
        self:_RefreshPressureStage("ClearTimeLimit", false)
    end
end

function GameManager:GetElapsedTime()
    return self.elapsedTime
end

function GameManager:GetRemainingTime()
    return self.remainingTime
end

function GameManager:GetPressureStage()
    return self.pressureStage
end

function GameManager:SetPressureStageOverride(pressure)
    local rawPressure = pressure
    pressure = normalize_pressure(pressure)
    if pressure == nil then
        print("[GameManager] Unknown pressure: " .. tostring(rawPressure))
        return false
    end

    self.manualPressureStage = pressure
    return self:_SetPressureStage(pressure, "SetPressureStageOverride", true)
end

function GameManager:ClearPressureStageOverride()
    self.manualPressureStage = nil
    return self:_RefreshPressureStage("ClearPressureStageOverride", true)
end

function GameManager:KillPlayer(reason)
    if self.isPlayerDead then
        return false
    end

    self.isPlayerDead = true
    self:_FireEvent("PlayerDead", reason or "PlayerDead")
    self:GameOver(reason or "PlayerDead")
    return true
end

function GameManager:IsPlaying()
    return self.state == self.State.Playing
end

function GameManager:GetState()
    return self.state
end

function GameManager:AdvanceAnomalyLoop()
    if self.state ~= self.State.Playing then
        return false
    end

    return AnomalyManager:SelectAndSpawn()
end

function GameManager:ReportAnomalyShot(actor)
    return AnomalyManager:ReportShot(actor)
end

function GameManager:GetActiveAnomalyTarget()
    return AnomalyManager:GetActiveTarget()
end

function GameManager:GetActiveAnomalyRuleName()
    return AnomalyManager:GetActiveRuleName()
end

return GameManager
