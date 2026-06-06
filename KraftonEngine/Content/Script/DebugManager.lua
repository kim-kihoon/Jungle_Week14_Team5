local DebugManager = {}

DebugManager.bEnabled = true

DebugManager.Scenarios = {
    {
        Key = "Numpad1",
        RuleName = "PhotoInvisible"
    },
    {
        Key = "Numpad2",
        RuleName = "NoShadow"
    },
    {
        Key = "Numpad3",
        RuleName = "OffscreenAnimation"
    }
}

function DebugManager:SetEnabled(bEnabled)
    self.bEnabled = bEnabled == true
end

function DebugManager:IsEnabled()
    return self.bEnabled == true
end

function DebugManager:LoadAnomalyScenario(gameManager, ruleName)
    local GameManager = gameManager
    if GameManager == nil or GameManager.DebugSpawnAnomalyRule == nil then
        print("[DebugManager] GameManager.DebugSpawnAnomalyRule unavailable")
        return false
    end

    local ok = GameManager:DebugSpawnAnomalyRule(ruleName)
    if ok then
        print("[DebugManager] Loaded anomaly scenario: " .. tostring(ruleName))
        return true
    end

    local reason = nil
    if GameManager.GetLastAnomalyError ~= nil then
        reason = GameManager:GetLastAnomalyError()
    end
    print("[DebugManager] Failed to load anomaly scenario: " .. tostring(ruleName) .. " reason=" .. tostring(reason))
    return false
end

function DebugManager:Tick(dt, gameManager)
    if not self:IsEnabled() then
        return
    end
    if Input == nil or Input.GetKeyDown == nil then
        return
    end

    for _, scenario in ipairs(self.Scenarios) do
        if Input.GetKeyDown(scenario.Key) then
            self:LoadAnomalyScenario(gameManager, scenario.RuleName)
            return
        end
    end
end

return DebugManager
