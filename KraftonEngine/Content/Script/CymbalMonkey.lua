local GameManager = require("GameManager")

local PRESSURE_STAGE_NORMAL = 1
local PRESSURE_STAGE_WARNING = 2
local PRESSURE_STAGE_FINAL_WARNING = 3
local PRESSURE_STAGE_MIN = PRESSURE_STAGE_NORMAL
local PRESSURE_STAGE_MAX = PRESSURE_STAGE_FINAL_WARNING

local WARNING_REMAINING_RATIO = 0.5
local FINAL_WARNING_REMAINING_RATIO = 0.2

local StageConfig = {
    [PRESSURE_STAGE_NORMAL] = {
        animationPath = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_SymbalSingle.uasset"
    },
    [PRESSURE_STAGE_WARNING] = {
        animationPath = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_Warning.uasset"
    },
    [PRESSURE_STAGE_FINAL_WARNING] = {
        animationPath = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_FinalWarning.uasset"
    }
}

local PlayRate = 1.0
local Mesh = nil
local CurrentStage = PRESSURE_STAGE_NORMAL
local ManualStage = nil
local bLoopPlaying = false
local bMissingMeshLogged = false

local function clamp_min(value, fallback, minimum)
    value = tonumber(value)
    if value == nil then
        return fallback
    end
    if value < minimum then
        return minimum
    end
    return value
end

local function clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

local function normalize_stage(stage)
    stage = tonumber(stage)
    if stage == nil then
        return nil
    end
    return math.floor(stage)
end

local function is_valid_stage(stage)
    stage = normalize_stage(stage)
    return stage ~= nil and StageConfig[stage] ~= nil
end

local function get_stage_from_time()
    local timeLimit = tonumber(GameManager.timeLimit)
    if timeLimit == nil or timeLimit <= 0 then
        return PRESSURE_STAGE_NORMAL
    end

    local remainingTime = tonumber(GameManager:GetRemainingTime()) or timeLimit
    local remainingRatio = remainingTime / timeLimit

    if remainingRatio <= FINAL_WARNING_REMAINING_RATIO then
        return PRESSURE_STAGE_FINAL_WARNING
    end
    if remainingRatio <= WARNING_REMAINING_RATIO then
        return PRESSURE_STAGE_WARNING
    end
    return PRESSURE_STAGE_NORMAL
end

local function resolve_pressure_stage()
    if is_valid_stage(ManualStage) then
        return ManualStage
    end
    return get_stage_from_time()
end

local function get_current_config()
    return StageConfig[CurrentStage] or StageConfig[PRESSURE_STAGE_NORMAL]
end

local function cache_mesh()
    if Mesh ~= nil then
        return Mesh
    end

    if obj ~= nil and obj.GetSkeletalMeshComponent ~= nil then
        Mesh = obj:GetSkeletalMeshComponent()
    end

    if Mesh == nil and not bMissingMeshLogged then
        bMissingMeshLogged = true
        print("[CymbalMonkey] SkeletalMeshComponent not found")
    end

    return Mesh
end

local function play_loop_stage()
    local mesh = cache_mesh()
    if mesh == nil then
        return false
    end

    local config = get_current_config()
    mesh:PlayAnimationByPath(config.animationPath, true)
    mesh:SetPlayRate(PlayRate)
    bLoopPlaying = true
    return true
end

local function stop_loop_stage()
    local mesh = cache_mesh()
    if mesh ~= nil and bLoopPlaying then
        mesh:StopAnimation()
    end

    bLoopPlaying = false
    return true
end

local function set_current_stage(stage, bPlayImmediately)
    stage = normalize_stage(stage)
    if not is_valid_stage(stage) then
        return false
    end

    local previousStage = CurrentStage
    local bStageChanged = previousStage ~= stage

    CurrentStage = stage

    if bPlayImmediately or bStageChanged then
        play_loop_stage()
    end

    return true
end

function SetPressureStage(stage)
    stage = normalize_stage(stage)
    if not is_valid_stage(stage) then
        print("[CymbalMonkey] Unknown pressure stage: " .. tostring(stage))
        return false
    end

    ManualStage = stage
    return set_current_stage(stage, true)
end

function ClearPressureStageOverride()
    ManualStage = nil
    return set_current_stage(resolve_pressure_stage(), false)
end

function SetPressureStageConfig(stage, config)
    stage = normalize_stage(stage)
    if not is_valid_stage(stage) then
        print("[CymbalMonkey] Unknown pressure stage: " .. tostring(stage))
        return false
    end
    if type(config) ~= "table" then
        print("[CymbalMonkey] SetPressureStageConfig expects a table")
        return false
    end

    local target = StageConfig[stage]
    if config.animationPath ~= nil then
        target.animationPath = tostring(config.animationPath)
    end

    if CurrentStage == stage then
        play_loop_stage()
    end

    return true
end

function SetPlayRate(playRate)
    PlayRate = clamp_min(playRate, PlayRate, 0.01)
    if bLoopPlaying then
        local mesh = cache_mesh()
        if mesh ~= nil then
            mesh:SetPlayRate(PlayRate)
        end
    end
    return true
end

function GetPlayRate()
    return PlayRate
end

function CalculatePlayRate(stage)
    stage = normalize_stage(stage) or CurrentStage
    local alpha = (stage - PRESSURE_STAGE_MIN) / (PRESSURE_STAGE_MAX - PRESSURE_STAGE_MIN)
    return clamp01(alpha)
end

function GetPressureStage()
    return CurrentStage
end

function BeginPlay()
    Mesh = nil
    cache_mesh()
    CurrentStage = resolve_pressure_stage()
    bLoopPlaying = false
    if GameManager:IsPlaying() then
        play_loop_stage()
    end
end

function EndPlay()
    stop_loop_stage()
    Mesh = nil
    ManualStage = nil
    CurrentStage = PRESSURE_STAGE_NORMAL
    bMissingMeshLogged = false
end

function Tick(dt)
    if not GameManager:IsPlaying() then
        stop_loop_stage()
        return
    end

    local nextStage = resolve_pressure_stage()
    set_current_stage(nextStage, false)
    if not bLoopPlaying then
        play_loop_stage()
    end
end
