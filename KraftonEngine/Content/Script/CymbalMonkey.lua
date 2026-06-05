local GameManager = require("GameManager")

local PRESSURE_ENTRY_STRIKE = 1
local PRESSURE_WARNING = 2
local PRESSURE_FINAL_WARNING = 3
local PRESSURE_MIN = PRESSURE_ENTRY_STRIKE
local PRESSURE_MAX = PRESSURE_FINAL_WARNING

local STATE_NONE = 0
local STATE_ENTRY = 1
local STATE_STRIKE = 2
local STATE_WARNING = 3
local STATE_FINAL_WARNING = 4

local WARNING_REMAINING_RATIO = 0.1
local FINAL_WARNING_REMAINING_RATIO = 0.1

local ENTRY_INTERVAL_MIN = 0.21
local ENTRY_INTERVAL_MAX = 4.0

local ENTRY_ANIMATION_PATH = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_ArmOnlyCymbalEntry.uasset"
local STRIKE_ANIMATION_PATH = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_ArmOnlyCymbalStrike.uasset"
local WARNING_ANIMATION_PATH = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_Warning.uasset"
local FINAL_WARNING_ANIMATION_PATH = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_FinalWarning.uasset"

local FINISH_EPSILON = 0.0001
local PlayRate = 1.0
local EntryTimeRate = 0.5
local ENTRY_TIME_RATE_MIN = 0.1
local ENTRY_TIME_RATE_MAX = 0.9

local Mesh = nil
local CurrentPressure = PRESSURE_ENTRY_STRIKE
local ManualPressure = nil
local CurrentState = STATE_NONE
local CurrentEntryInterval = ENTRY_INTERVAL_MAX
local EntryCoroutine = nil
local EntryCoroutineGeneration = 0
local bAnimationPlaying = false
local bMissingMeshLogged = false

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

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

local function normalize_pressure(pressure)
    pressure = tonumber(pressure)
    if pressure == nil then
        return nil
    end
    pressure = math.floor(pressure)
    if pressure < PRESSURE_MIN or pressure > PRESSURE_MAX then
        return nil
    end
    return pressure
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

local function get_remaining_ratio()
    local timeLimit = tonumber(GameManager.timeLimit)
    if timeLimit == nil or timeLimit <= 0 then
        return 1.0
    end

    local remainingTime = tonumber(GameManager:GetRemainingTime()) or timeLimit
    return clamp(remainingTime / timeLimit, 0.0, 1.0)
end

local function get_pressure_from_time()
    local remainingRatio = get_remaining_ratio()

    if remainingRatio <= FINAL_WARNING_REMAINING_RATIO then
        return PRESSURE_FINAL_WARNING
    end
    if remainingRatio <= WARNING_REMAINING_RATIO then
        return PRESSURE_WARNING
    end
    return PRESSURE_ENTRY_STRIKE
end

local function resolve_pressure()
    local pressure = normalize_pressure(ManualPressure)
    if pressure ~= nil then
        return pressure
    end
    return get_pressure_from_time()
end

local function calculate_entry_interval()
    local remainingRatio = get_remaining_ratio()

    if remainingRatio >= 1.0 then
        return ENTRY_INTERVAL_MAX
    end
    if remainingRatio <= WARNING_REMAINING_RATIO then
        return ENTRY_INTERVAL_MIN
    end

    local alpha = (remainingRatio - WARNING_REMAINING_RATIO) / (1.0 - WARNING_REMAINING_RATIO)
    return ENTRY_INTERVAL_MIN + (ENTRY_INTERVAL_MAX - ENTRY_INTERVAL_MIN) * alpha
end

local function calculate_base_entry_time_rate()
    local remainingRatio = get_remaining_ratio()

    if remainingRatio >= 1.0 then
        return ENTRY_TIME_RATE_MIN
    end
    if remainingRatio <= WARNING_REMAINING_RATIO then
        return ENTRY_TIME_RATE_MAX
    end

    local alpha = (1.0 - remainingRatio) / (1.0 - WARNING_REMAINING_RATIO)
    return ENTRY_TIME_RATE_MIN + (ENTRY_TIME_RATE_MAX - ENTRY_TIME_RATE_MIN) * alpha
end

local function get_current_animation_length()
    local mesh = cache_mesh()
    if mesh == nil or mesh.GetCurrentAnimationLength == nil then
        return 0
    end
    return tonumber(mesh:GetCurrentAnimationLength()) or 0
end

local function calculate_entry_time_rate_for_interval(interval)
    local length = get_current_animation_length()
    if length > 0 and interval > 0 then
        return length / interval
    end
    return calculate_base_entry_time_rate()
end

local function play_animation(path, looping, rate)
    local mesh = cache_mesh()
    if mesh == nil then
        return false
    end

    local success = mesh:PlayAnimationByPath(path, looping)
    if success == false then
        print("[CymbalMonkey] Failed to play animation: " .. tostring(path))
        bAnimationPlaying = false
        return false
    end

    mesh:SetPlayRate(rate)
    bAnimationPlaying = true
    return true
end

local function play_entry_for_interval(interval)
    local baseRate = calculate_base_entry_time_rate()
    if not play_animation(ENTRY_ANIMATION_PATH, false, baseRate) then
        return false
    end

    EntryTimeRate = calculate_entry_time_rate_for_interval(interval)

    local mesh = cache_mesh()
    if mesh ~= nil then
        mesh:SetPlayRate(EntryTimeRate)
    end

    CurrentState = STATE_ENTRY
    return true
end

local function stop_pressure_one_coroutine()
    EntryCoroutineGeneration = EntryCoroutineGeneration + 1
    EntryCoroutine = nil
end

local function stop_animation()
    stop_pressure_one_coroutine()

    local mesh = cache_mesh()
    if mesh ~= nil and bAnimationPlaying then
        mesh:StopAnimation()
    end

    bAnimationPlaying = false
    CurrentState = STATE_NONE
end

local function set_state(state, force)
    if not force and CurrentState == state and bAnimationPlaying then
        return true
    end

    if state == STATE_ENTRY then
        CurrentEntryInterval = calculate_entry_interval()
        return play_entry_for_interval(CurrentEntryInterval)
    end
    if state == STATE_STRIKE then
        CurrentState = STATE_STRIKE
        return play_animation(STRIKE_ANIMATION_PATH, false, PlayRate)
    end
    if state == STATE_WARNING then
        stop_pressure_one_coroutine()
        CurrentState = STATE_WARNING
        return play_animation(WARNING_ANIMATION_PATH, true, PlayRate)
    end
    if state == STATE_FINAL_WARNING then
        stop_pressure_one_coroutine()
        CurrentState = STATE_FINAL_WARNING
        return play_animation(FINAL_WARNING_ANIMATION_PATH, true, PlayRate)
    end

    stop_animation()
    return true
end

local function is_current_animation_finished()
    local mesh = cache_mesh()
    if mesh == nil then
        return false
    end

    if mesh.IsCurrentAnimationFinished ~= nil then
        return mesh:IsCurrentAnimationFinished()
    end

    if mesh.GetCurrentAnimationTime == nil or mesh.GetCurrentAnimationLength == nil then
        return false
    end

    local currentTime = tonumber(mesh:GetCurrentAnimationTime()) or 0
    local length = tonumber(mesh:GetCurrentAnimationLength()) or 0
    return length > 0 and currentTime >= length - FINISH_EPSILON
end

local function is_pressure_one_coroutine_valid(generation)
    return generation == EntryCoroutineGeneration and
        GameManager:IsPlaying() and
        CurrentPressure == PRESSURE_ENTRY_STRIKE
end

local function wait_seconds(seconds, generation)
    local elapsed = 0
    while elapsed < seconds do
        if not is_pressure_one_coroutine_valid(generation) then
            return false
        end

        local dt = coroutine.yield()
        elapsed = elapsed + (tonumber(dt) or 0)
    end
    return is_pressure_one_coroutine_valid(generation)
end

local function wait_until_animation_finished(generation)
    while not is_current_animation_finished() do
        if not is_pressure_one_coroutine_valid(generation) then
            return false
        end
        coroutine.yield()
    end
    return is_pressure_one_coroutine_valid(generation)
end

local function pressure_one_loop(generation)
    while is_pressure_one_coroutine_valid(generation) do
        CurrentEntryInterval = calculate_entry_interval()
        if not play_entry_for_interval(CurrentEntryInterval) then
            return
        end

        if not wait_seconds(CurrentEntryInterval, generation) then
            return
        end

        if not set_state(STATE_STRIKE, true) then
            return
        end

        if not wait_until_animation_finished(generation) then
            return
        end
    end
end

local function resume_pressure_one_coroutine(dt)
    if EntryCoroutine == nil then
        return
    end

    if coroutine.status(EntryCoroutine) == "dead" then
        EntryCoroutine = nil
        return
    end

    local ok, err = coroutine.resume(EntryCoroutine, dt or 0)
    if not ok then
        print("[CymbalMonkey] Pressure coroutine error: " .. tostring(err))
        EntryCoroutine = nil
        return
    end

    if EntryCoroutine ~= nil and coroutine.status(EntryCoroutine) == "dead" then
        EntryCoroutine = nil
    end
end

local function start_pressure_one_coroutine()
    stop_pressure_one_coroutine()

    local generation = EntryCoroutineGeneration
    EntryCoroutine = coroutine.create(function()
        pressure_one_loop(generation)
    end)

    resume_pressure_one_coroutine(0)
end

local function enter_pressure(pressure)
    pressure = normalize_pressure(pressure) or PRESSURE_ENTRY_STRIKE
    CurrentPressure = pressure

    if pressure == PRESSURE_ENTRY_STRIKE then
        start_pressure_one_coroutine()
        return true
    end
    if pressure == PRESSURE_WARNING then
        return set_state(STATE_WARNING, true)
    end
    if pressure == PRESSURE_FINAL_WARNING then
        return set_state(STATE_FINAL_WARNING, true)
    end

    return false
end

function SetPressureStage(pressure)
    pressure = normalize_pressure(pressure)
    if pressure == nil then
        print("[CymbalMonkey] Unknown pressure: " .. tostring(pressure))
        return false
    end

    ManualPressure = pressure
    if GameManager:IsPlaying() then
        return enter_pressure(pressure)
    end

    CurrentPressure = pressure
    return true
end

function ClearPressureStageOverride()
    ManualPressure = nil
    if GameManager:IsPlaying() then
        return enter_pressure(resolve_pressure())
    end
    CurrentPressure = resolve_pressure()
    return true
end

function SetPlayRate(playRate)
    PlayRate = clamp_min(playRate, PlayRate, 0.01)

    local mesh = cache_mesh()
    if mesh ~= nil and bAnimationPlaying and CurrentState ~= STATE_ENTRY then
        mesh:SetPlayRate(PlayRate)
    end

    return true
end

function GetPlayRate()
    return PlayRate
end

function SetEntryTimeRate(rate)
    local mesh = cache_mesh()
    if mesh ~= nil and bAnimationPlaying and CurrentState == STATE_ENTRY then
        EntryTimeRate = calculate_entry_time_rate_for_interval(CurrentEntryInterval)
        mesh:SetPlayRate(EntryTimeRate)
    else
        EntryTimeRate = calculate_base_entry_time_rate()
    end

    return true
end

function GetEntryTimeRate()
    return EntryTimeRate
end

function GetEntryInterval()
    if CurrentPressure == PRESSURE_ENTRY_STRIKE then
        return CurrentEntryInterval
    end
    return calculate_entry_interval()
end

function SetEntryIntervalRange(minSeconds, maxSeconds)
    minSeconds = clamp_min(minSeconds, ENTRY_INTERVAL_MIN, 0.01)
    maxSeconds = clamp_min(maxSeconds, ENTRY_INTERVAL_MAX, 0.01)

    if minSeconds > maxSeconds then
        minSeconds, maxSeconds = maxSeconds, minSeconds
    end

    ENTRY_INTERVAL_MIN = minSeconds
    ENTRY_INTERVAL_MAX = maxSeconds
    CurrentEntryInterval = calculate_entry_interval()

    if CurrentPressure == PRESSURE_ENTRY_STRIKE and GameManager:IsPlaying() then
        enter_pressure(PRESSURE_ENTRY_STRIKE)
    end

    return true
end

function GetPressureStage()
    return CurrentPressure
end

function GetCymbalState()
    return CurrentState
end

function BeginPlay()
    Mesh = nil
    bMissingMeshLogged = false
    cache_mesh()

    CurrentPressure = resolve_pressure()
    CurrentState = STATE_NONE
    CurrentEntryInterval = calculate_entry_interval()
    bAnimationPlaying = false
    stop_pressure_one_coroutine()

    if GameManager:IsPlaying() then
        enter_pressure(CurrentPressure)
    end
end

function EndPlay()
    stop_animation()
    Mesh = nil
    ManualPressure = nil
    CurrentPressure = PRESSURE_ENTRY_STRIKE
    CurrentState = STATE_NONE
    CurrentEntryInterval = ENTRY_INTERVAL_MAX
    bMissingMeshLogged = false
end

function Tick(dt)
    if not GameManager:IsPlaying() then
        stop_animation()
        return
    end

    local nextPressure = resolve_pressure()
    if nextPressure ~= CurrentPressure then
        enter_pressure(nextPressure)
        return
    end

    if CurrentPressure == PRESSURE_ENTRY_STRIKE then
        if EntryCoroutine == nil then
            start_pressure_one_coroutine()
        else
            resume_pressure_one_coroutine(dt)
        end
        return
    end

    if not bAnimationPlaying then
        enter_pressure(CurrentPressure)
    end
end
