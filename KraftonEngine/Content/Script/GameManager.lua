local GameManager = {}
local AnomalyManager = require("AnomalyManager")
local LeaderboardManager = require("LeaderboardManager")
local PlacementManager = require("PlacementManager")
local JumpScareManager = require("JumpScareManager")
local LoopManager = require("LoopManager")

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
GameManager.totalGameTime = 0
GameManager.remainingTime = 0
GameManager.timeLimit = nil
GameManager.isPlayerDead = false
GameManager.bLoopStopped = false
GameManager.bCymbalMonkeyCycleStarted = false
GameManager.pressureStage = GameManager.Pressure.EntryStrike
GameManager.manualPressureStage = nil
GameManager.AnomalyPlacementTemplateSetName = "Runtime"
GameManager.AnomalyPlacementTemplateExtension = ".ActorTemplate"
GameManager.AnomalyPlacementTemplateSets = {
    Debug = {
        Directory = "Content/Blueprint/AnomaliesPlacement/Debug",
        Recursive = false
    },
    Runtime = {
        Directory = "Content/Blueprint/AnomaliesPlacement/Runtime",
        Recursive = false
    }
}
GameManager.ActiveAnomalyPlacementRecord = nil
GameManager.LastAnomalyPlacementError = nil

GameManager._listeners = {
    StateChanged = {},
    ScoreChanged = {},
    PlayerDead = {},
    TimeExpired = {},
    PressureChanged = {},
    LoopStopped = {},
    LoopRested = {},
    CymbalMonkeyCycleStarted = {},
    CymbalMonkeyCycleReset = {}
}

local WARNING_REMAINING_RATIO = 0.1
local FINAL_WARNING_REMAINING_RATIO = 0.1
local ANOMALY_PLACEMENT_RECORD_ID = "GameManager_AnomalyPlacement"
local bAnomalyPlacementRandomSeeded = false

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

local function make_random_seed(timeSeconds)
    local rawSeed = math.floor((tonumber(timeSeconds) or 0) * 1000000)
    if rawSeed <= 0 then
        return nil
    end
    return (rawSeed % 2147483646) + 1
end

local function seed_anomaly_placement_random_once()
    if bAnomalyPlacementRandomSeeded then
        return
    end

    local seed = nil
    if World ~= nil and World.GetRealTimeSeconds ~= nil then
        seed = make_random_seed(World.GetRealTimeSeconds())
    end

    if seed ~= nil then
        math.randomseed(seed)
        bAnomalyPlacementRandomSeeded = true
    end
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

function GameManager:_ClearAnomalyPlacement()
    local record = self.ActiveAnomalyPlacementRecord
    self.ActiveAnomalyPlacementRecord = nil

    if record == nil then
        return false
    end

    PlacementManager:Destroy(record)
    return true
end

function GameManager:_GetAnomalyPlacementTemplateSet()
    local setName = self.AnomalyPlacementTemplateSetName
    local templateSet = self.AnomalyPlacementTemplateSets[setName]
    if templateSet == nil then
        self.LastAnomalyPlacementError = "Anomaly placement template set not found: " .. tostring(setName)
        return nil
    end

    if type(templateSet.Directory) ~= "string" or templateSet.Directory == "" then
        self.LastAnomalyPlacementError = "Anomaly placement directory is empty: " .. tostring(setName)
        return nil
    end

    return templateSet
end

function GameManager:_FindAnomalyPlacementTemplates(templateSet)
    if World == nil or World.FindFilesByExtension == nil then
        self.LastAnomalyPlacementError = "World.FindFilesByExtension unavailable"
        return nil
    end

    local templates = World.FindFilesByExtension(
        templateSet.Directory,
        self.AnomalyPlacementTemplateExtension,
        templateSet.Recursive == true
    )

    if type(templates) ~= "table" then
        self.LastAnomalyPlacementError = "Anomaly placement template query failed"
        return nil
    end

    if #templates <= 0 then
        self.LastAnomalyPlacementError = "Anomaly placement template not found: " .. tostring(templateSet.Directory)
        return nil
    end

    return templates
end

function GameManager:_SpawnRandomAnomalyPlacement(reason)
    seed_anomaly_placement_random_once()

    local templateSet = self:_GetAnomalyPlacementTemplateSet()
    if templateSet == nil then
        return false
    end

    local templates = self:_FindAnomalyPlacementTemplates(templateSet)
    if templates == nil then
        return false
    end

    local templatePath = templates[math.random(1, #templates)]
    local record, message = PlacementManager:Spawn(templatePath, {
        Id = ANOMALY_PLACEMENT_RECORD_ID
    })
    if record == nil then
        self.LastAnomalyPlacementError = "Anomaly placement spawn failed: " .. tostring(message or templatePath)
        return false
    end

    self.ActiveAnomalyPlacementRecord = record
    self.LastAnomalyPlacementError = nil
    return true
end

function GameManager:_SetupAnomaly(reason)
    reason = reason or "SetupAnomaly"
    AnomalyManager:DespawnCurrent(reason)
    self:_ClearAnomalyPlacement()
    local bPlacementReady = self:_SpawnRandomAnomalyPlacement(reason)
    local bAnomalyReady = AnomalyManager:SelectAndSpawn()
    return bPlacementReady and bAnomalyReady
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

function GameManager:OnLoopStopped(callback)
    return self:AddListener("LoopStopped", callback)
end

function GameManager:OnLoopRested(callback)
    return self:AddListener("LoopRested", callback)
end

function GameManager:OnCymbalMonkeyCycleStarted(callback)
    return self:AddListener("CymbalMonkeyCycleStarted", callback)
end

function GameManager:OnCymbalMonkeyCycleReset(callback)
    return self:AddListener("CymbalMonkeyCycleReset", callback)
end

function GameManager:IsCymbalMonkeyCycleStarted()
    return LoopManager:IsCymbalMonkeyCycleStarted()
end

function GameManager:StartCymbalMonkeyCycle()
    local bStarted = LoopManager:StartCymbalMonkeyCycle(self)
    self.bCymbalMonkeyCycleStarted = LoopManager:IsCymbalMonkeyCycleStarted()
    return bStarted
end

function GameManager:ResetCymbalMonkeyCycle()
    local bWasStarted = LoopManager:ResetCymbalMonkeyCycle(self, "ResetCymbalMonkeyCycle")
    self.bCymbalMonkeyCycleStarted = LoopManager:IsCymbalMonkeyCycleStarted()
    return bWasStarted
end

function GameManager:IsLoopStopped()
    return LoopManager:IsLoopStopped()
end

function GameManager:StopLoop(reason)
    local bStopped = LoopManager:StopLoop(self, reason)
    self.bLoopStopped = LoopManager:IsLoopStopped()
    return bStopped
end

function GameManager:RestLoop(reason)
    reason = reason or "RestLoop"
    return self:OnLoopStart(reason)
end

function GameManager:Reset()
    AnomalyManager:Reset()
    JumpScareManager:DeactivateAll()
    self:_ClearAnomalyPlacement()
    self.LastAnomalyPlacementError = nil
    self.score = 0
    self.elapsedTime = 0
    self.totalGameTime = 0
    self.remainingTime = self.timeLimit or 0
    self.isPlayerDead = false
    LoopManager:Reset()
    self.bLoopStopped = LoopManager:IsLoopStopped()
    self.bCymbalMonkeyCycleStarted = LoopManager:IsCymbalMonkeyCycleStarted()
    self.manualPressureStage = nil
    self:_SetPressureStage(self.Pressure.EntryStrike, "Reset", false)
    self:_SetState(self.State.Ready, "Reset")
end

function GameManager:StartGame()
    self.elapsedTime = 0
    self.totalGameTime = 0
    self.remainingTime = self.timeLimit or 0
    self.isPlayerDead = false
    LoopManager:StartStopped()
    self.bLoopStopped = LoopManager:IsLoopStopped()
    self.bCymbalMonkeyCycleStarted = LoopManager:IsCymbalMonkeyCycleStarted()
    self:_SetState(self.State.Playing, "StartGame")
    self:_RefreshPressureStage("StartGame", true)
    self:_SetupAnomaly("StartGame")
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
    JumpScareManager:DeactivateAll()
    self:_ClearAnomalyPlacement()
    self.LastAnomalyPlacementError = nil
    LoopManager:Reset()
    self.bLoopStopped = LoopManager:IsLoopStopped()
    self.bCymbalMonkeyCycleStarted = LoopManager:IsCymbalMonkeyCycleStarted()
    self:_SetPressureStage(self.Pressure.EntryStrike, reason or "GameOver", false)
    return self:_SetState(self.State.GameOver, reason or "GameOver")
end

function GameManager:ClearGame(reason)
    if self.state == self.State.Clear then
        return false
    end

    local clearReason = reason or "ClearGame"
    local createdAtSeconds = 0
    if World ~= nil and World.GetRealTimeSeconds ~= nil then
        createdAtSeconds = tonumber(World.GetRealTimeSeconds()) or 0
    end

    LeaderboardManager:AddClearRecord({
        TotalTimeSeconds = self.totalGameTime,
        ElapsedTimeSeconds = self.elapsedTime,
        Score = self.score,
        ClearReason = clearReason,
        CreatedAtSeconds = createdAtSeconds
    })

    AnomalyManager:Reset()
    JumpScareManager:DeactivateAll()
    self:_ClearAnomalyPlacement()
    self.LastAnomalyPlacementError = nil
    LoopManager:Reset()
    self.bLoopStopped = LoopManager:IsLoopStopped()
    self.bCymbalMonkeyCycleStarted = LoopManager:IsCymbalMonkeyCycleStarted()
    self:_SetPressureStage(self.Pressure.EntryStrike, clearReason, false)
    return self:_SetState(self.State.Clear, clearReason)
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

    self.totalGameTime = self.totalGameTime + dt

    AnomalyManager:Tick(dt)
    if LoopManager:IsLoopStopped() then
        return
    end

    if not LoopManager:IsCymbalMonkeyCycleStarted() then
        return
    end

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

function GameManager:GetTotalGameTime()
    return self.totalGameTime
end

function GameManager:GetLeaderboardEntries()
    return LeaderboardManager:GetEntries()
end

function GameManager:GetLeaderboardEntryCount()
    return LeaderboardManager:GetEntryCount()
end

function GameManager:GetLeaderboardEntry(index)
    return LeaderboardManager:GetEntry(index)
end

function GameManager:GetBestLeaderboardEntry()
    return LeaderboardManager:GetBestEntry()
end

function GameManager:GetLastLeaderboardRecord()
    return LeaderboardManager:GetLastRecord()
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

function GameManager:OnWarp(reason)
    local bWarped = LoopManager:OnWarp(self, reason, function(setupReason)
        return self:_SetupAnomaly(setupReason)
    end)
    self.bLoopStopped = LoopManager:IsLoopStopped()
    self.bCymbalMonkeyCycleStarted = LoopManager:IsCymbalMonkeyCycleStarted()
    return bWarped
end

function GameManager:OnLoopStart(reason)
    local bStarted = LoopManager:OnLoopStart(self, reason, function(startReason)
        self.remainingTime = self.timeLimit or 0
        self:_RefreshPressureStage(startReason, true)
        JumpScareManager:ActivateRandom()
    end)
    self.bLoopStopped = LoopManager:IsLoopStopped()
    self.bCymbalMonkeyCycleStarted = LoopManager:IsCymbalMonkeyCycleStarted()
    return bStarted
end

function GameManager:SetJumpScareActiveCount(count)
    return JumpScareManager:SetActiveCount(count)
end

function GameManager:GetJumpScareActiveCount()
    return JumpScareManager:GetActiveCount()
end

function GameManager:GetLastJumpScareError()
    return JumpScareManager:GetLastError()
end

function GameManager:AdvanceAnomalyLoop()
    if self.state ~= self.State.Playing then
        return false
    end

    local bWarped = self:OnWarp("AdvanceAnomalyLoop")
    local bStarted = self:OnLoopStart("AdvanceAnomalyLoop")
    return bWarped and bStarted
end

function GameManager:ReportAnomalyShot(actor, hit)
    local bHitAnomaly = AnomalyManager:ReportShot(actor, hit)
    if bHitAnomaly then
        self:StopLoop("AnomalyShot")
    end
    return bHitAnomaly
end

function GameManager:GetActiveAnomalyTarget()
    return AnomalyManager:GetActiveTarget()
end

function GameManager:GetActiveAnomalyRuleName()
    return AnomalyManager:GetActiveRuleName()
end

function GameManager:GetLastAnomalyError()
    return AnomalyManager:GetLastError()
end

function GameManager:SetAnomalyPlacementTemplateSetName(name)
    if type(name) ~= "string" or self.AnomalyPlacementTemplateSets[name] == nil then
        self.LastAnomalyPlacementError = "Unknown anomaly placement template set: " .. tostring(name)
        return false
    end

    self.AnomalyPlacementTemplateSetName = name
    self.LastAnomalyPlacementError = nil
    return true
end

function GameManager:GetAnomalyPlacementTemplateSetName()
    return self.AnomalyPlacementTemplateSetName
end

function GameManager:GetLastAnomalyPlacementError()
    return self.LastAnomalyPlacementError
end

function GameManager:DebugSpawnAnomalyRule(ruleName)
    if self.state ~= self.State.Playing then
        print("[GameManager] DebugSpawnAnomalyRule ignored: game is not playing")
        return false
    end

    return AnomalyManager:SelectAndSpawnRule(ruleName)
end

return GameManager
