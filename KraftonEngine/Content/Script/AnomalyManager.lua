local AnomalyManager = {}

local PhotoInvisible = require("Anomalies/PhotoInvisible")
local NoShadow = require("Anomalies/NoShadow")
local OffscreenAnimation = require("Anomalies/OffscreenAnimation")
local OffscreenFacePlayer = require("Anomalies/OffscreenFacePlayer")
local BlackPhoto = require("Anomalies/BlackPhoto")

AnomalyManager.Tags = {
    Candidate = "AnomalyCandidate",
    ActiveTarget = "ActiveAnomalyTarget",
    PhotoInvisible = "PhotoInvisible",
    PhotoBlackoutTarget = "PhotoBlackoutTarget"
}

AnomalyManager.Rules = {
    PhotoInvisible,
    NoShadow,
    OffscreenAnimation,
    OffscreenFacePlayer,
    BlackPhoto
}

AnomalyManager.Active = nil
AnomalyManager.LastError = nil

local seeded = false

local function make_seed(timeSeconds)
    local rawSeed = math.floor((tonumber(timeSeconds) or 0) * 1000000)
    if rawSeed <= 0 then
        return nil
    end
    return (rawSeed % 2147483646) + 1
end

local function seed_random_once()
    if seeded then
        return
    end

    local seed = nil
    if World ~= nil and World.GetRealTimeSeconds ~= nil then
        seed = make_seed(World.GetRealTimeSeconds())
    end

    if seed ~= nil then
        math.randomseed(seed)
        seeded = true
    end
end

local function is_valid_actor(actor)
    if actor == nil then
        return false
    end
    if actor.IsValid == nil then
        return true
    end
    return actor:IsValid()
end

local function get_rule_name(rule)
    return rule and rule.Name or "Unknown"
end

local function safe_call(rule, function_name, context)
    local fn = rule and rule[function_name]
    if type(fn) ~= "function" then
        return true
    end

    local ok, result, message = pcall(fn, rule, context)
    if not ok then
        return false, result
    end
    return result ~= false, message
end

function AnomalyManager:_BuildContext(target, rule)
    return {
        Manager = self,
        Target = target,
        Rule = rule,
        Tags = self.Tags,
        State = {}
    }
end

function AnomalyManager:_GetCandidates()
    local candidates = {}
    if World == nil or World.FindActorsByTag == nil then
        self.LastError = "World.FindActorsByTag unavailable"
        return candidates
    end

    local found = World.FindActorsByTag(self.Tags.Candidate)
    if found == nil then
        return candidates
    end

    for _, actor in pairs(found) do
        if is_valid_actor(actor) then
            table.insert(candidates, actor)
        end
    end

    return candidates
end

function AnomalyManager:_FindRuleByName(ruleName)
    if ruleName == nil then
        return nil
    end

    for _, rule in ipairs(self.Rules) do
        if get_rule_name(rule) == ruleName then
            return rule
        end
    end

    return nil
end

function AnomalyManager:_ActivateRule(target, rule)
    local context = self:_BuildContext(target, rule)

    local ok, message = safe_call(rule, "Spawn", context)
    if not ok then
        self.LastError = "Spawn failed: " .. get_rule_name(rule) .. " target=" .. target.Name .. " reason=" .. tostring(message)
        return false
    end

    local hadActiveTag = target:HasTag(self.Tags.ActiveTarget)
    if not hadActiveTag then
        target:AddTag(self.Tags.ActiveTarget)
    end

    self.Active = {
        Target = target,
        Rule = rule,
        Context = context,
        AddedActiveTag = not hadActiveTag,
        bCleared = false
    }

    print("[AnomalyManager] Active anomaly=" .. get_rule_name(rule) .. " target=" .. target.Name)
    return true
end

function AnomalyManager:HasActiveAnomaly()
    return self.Active ~= nil and is_valid_actor(self.Active.Target)
end

function AnomalyManager:GetActiveTarget()
    if not self:HasActiveAnomaly() then
        return nil
    end
    return self.Active.Target
end

function AnomalyManager:GetActiveRuleName()
    if self.Active == nil then
        return nil
    end
    return get_rule_name(self.Active.Rule)
end

function AnomalyManager:GetLastError()
    return self.LastError
end

function AnomalyManager:DespawnCurrent(reason)
    local active = self.Active
    self.Active = nil

    if active == nil then
        return false
    end

    if is_valid_actor(active.Target) and active.AddedActiveTag then
        active.Target:RemoveTag(self.Tags.ActiveTarget)
    end

    local context = active.Context
    if context ~= nil then
        context.Reason = reason
        safe_call(active.Rule, "Despawn", context)
    end

    return true
end

function AnomalyManager:SelectAndSpawn()
    seed_random_once()
    self:DespawnCurrent("SelectAndSpawn")
    self.LastError = nil

    local candidates = self:_GetCandidates()
    if #candidates <= 0 then
        self.LastError = "AnomalyCandidate tag actor not found"
        print("[AnomalyManager] " .. self.LastError)
        return false
    end

    if #self.Rules <= 0 then
        self.LastError = "Anomaly rule pool is empty"
        print("[AnomalyManager] " .. self.LastError)
        return false
    end

    local target = candidates[math.random(1, #candidates)]
    local rule = self.Rules[math.random(1, #self.Rules)]
    if not self:_ActivateRule(target, rule) then
        print("[AnomalyManager] " .. self.LastError)
        return false
    end

    return true
end

function AnomalyManager:SelectAndSpawnRule(ruleName)
    seed_random_once()
    self:DespawnCurrent("SelectAndSpawnRule")
    self.LastError = nil

    local rule = self:_FindRuleByName(ruleName)
    if rule == nil then
        self.LastError = "Anomaly rule not found: " .. tostring(ruleName)
        print("[AnomalyManager] " .. self.LastError)
        return false
    end

    local candidates = self:_GetCandidates()
    if #candidates <= 0 then
        self.LastError = "AnomalyCandidate tag actor not found"
        print("[AnomalyManager] " .. self.LastError)
        return false
    end

    local startIndex = math.random(1, #candidates)
    for offset = 0, #candidates - 1 do
        local index = ((startIndex + offset - 1) % #candidates) + 1
        if self:_ActivateRule(candidates[index], rule) then
            return true
        end
    end

    print("[AnomalyManager] " .. self.LastError)
    return false
end

function AnomalyManager:Tick(dt)
    local active = self.Active
    if active == nil then
        return
    end

    if not is_valid_actor(active.Target) then
        self:DespawnCurrent("TargetInvalid")
        return
    end

    if active.bCleared then
        return
    end

    active.Context.DeltaTime = dt
    safe_call(active.Rule, "Tick", active.Context)

    local ok, cleared = pcall(function()
        if type(active.Rule.IsCleared) ~= "function" then
            return false
        end
        return active.Rule:IsCleared(active.Context)
    end)

    if ok and cleared then
        self:OnClear(active, "RuleCleared")
    end
end

function AnomalyManager:OnClear(active, reason)
    if active == nil or active.bCleared then
        return false
    end

    active.bCleared = true
    if active.Context ~= nil and active.Context.State ~= nil then
        active.Context.State.bCleared = true
        active.Context.ClearReason = reason or "Clear"
    end
    return true
end

function AnomalyManager:ReportShot(actor)
    if actor == nil or self.Active == nil then
        return false
    end

    local active = self.Active
    if not is_valid_actor(active.Target) then
        self:DespawnCurrent("TargetInvalid")
        return false
    end

    local bHitActiveTarget = actor == active.Target
    if not bHitActiveTarget and actor.HasTag ~= nil then
        bHitActiveTarget = actor:HasTag(self.Tags.ActiveTarget)
    end

    if not bHitActiveTarget then
        return false
    end

    return self:OnClear(active, "Shot")
end

function AnomalyManager:Reset()
    self:DespawnCurrent("Reset")
    self.LastError = nil
end

return AnomalyManager
