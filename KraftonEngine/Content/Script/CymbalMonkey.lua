local GameManager = require("GameManager")

local PRESSURE_ENTRY_STRIKE = GameManager.Pressure and GameManager.Pressure.EntryStrike or 1
local PRESSURE_WARNING = GameManager.Pressure and GameManager.Pressure.Warning or 2
local PRESSURE_FINAL_WARNING = GameManager.Pressure and GameManager.Pressure.FinalWarning or 3
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
local INIT_POSITION_TAG = "CymbalsMonkeyInitPosition"
local POSITION_CANDIDATE_TAG = "CymbalsMonkeyPositionCandidate"
local TELEPORT_TRACE_HEIGHT_OFFSET = 0.2
local TELEPORT_FLOOR_TRACE_UP = 2.0
local TELEPORT_FLOOR_TRACE_DOWN = 20.0
local RAD_TO_DEG = 57.29577951308232
local PlayRate = 1.0
local EntryTimeRate = 0.5
local ENTRY_TIME_RATE_MIN = 0.1
local ENTRY_TIME_RATE_MAX = 0.9

local Mesh = nil
local CurrentPressure = PRESSURE_ENTRY_STRIKE
local CurrentState = STATE_NONE
local CurrentEntryInterval = ENTRY_INTERVAL_MAX
local EntryCoroutine = nil
local EntryCoroutineGeneration = 0
local bAnimationPlaying = false
local bMissingMeshLogged = false
local PressureChangedHandle = nil
local LoopStoppedHandle = nil
local LoopRestedHandle = nil
local bObservedSinceTeleport = false
local bMonkeyAtInitPosition = true

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

local function is_loop_stopped()
    return GameManager.IsLoopStopped ~= nil and GameManager:IsLoopStopped()
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

local function get_actor_location(actor)
    if actor == nil then
        return nil
    end
    if actor.GetLocation ~= nil then
        return actor:GetLocation()
    end
    return actor.Location
end

local function get_actor_rotation(actor)
    if actor == nil then
        return nil
    end
    if actor.GetRotation ~= nil then
        return actor:GetRotation()
    end
    return actor.Rotation
end

local function set_actor_location(actor, location)
    if actor == nil or location == nil then
        return false
    end
    if actor.SetLocation ~= nil then
        actor:SetLocation(location)
    else
        actor.Location = location
    end
    return true
end

local function set_actor_rotation(actor, rotation)
    if actor == nil or rotation == nil then
        return false
    end
    actor.Rotation = rotation
    return true
end

local function get_trace_location(actor)
    local location = get_actor_location(actor)
    if location == nil then
        return nil
    end
    return location + Vec3(0.0, 0.0, TELEPORT_TRACE_HEIGHT_OFFSET)
end

local function snap_location_to_floor(location)
    if World == nil or World.LineTrace == nil or location == nil then
        return location
    end

    local startLocation = location + Vec3(0.0, 0.0, TELEPORT_FLOOR_TRACE_UP)
    local endLocation = location - Vec3(0.0, 0.0, TELEPORT_FLOOR_TRACE_DOWN)
    local hit = World.LineTrace(startLocation, endLocation, obj)
    if hit ~= nil and hit.Hit and hit.Location ~= nil then
        return Vec3(location.X, location.Y, hit.Location.Z)
    end

    return location
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

local function atan2(y, x)
    if math.atan2 ~= nil then
        return math.atan2(y, x)
    end
    return math.atan(y, x)
end

local function make_yaw_rotation_to_player(location)
    local player = get_player_pawn()
    local playerLocation = get_actor_location(player)
    if location == nil or playerLocation == nil then
        return Vec3(0.0, 0.0, 0.0)
    end

    local delta = playerLocation - location
    if math.abs(delta.X) < 0.0001 and math.abs(delta.Y) < 0.0001 then
        return Vec3(0.0, 0.0, 0.0)
    end

    return Vec3(0.0, 0.0, atan2(delta.Y, delta.X) * RAD_TO_DEG)
end

local function get_player_camera()
    if CameraManager ~= nil and CameraManager.GetActiveCamera ~= nil then
        local activeCamera = CameraManager.GetActiveCamera()
        if activeCamera ~= nil then
            return activeCamera
        end
    end

    local player = get_player_pawn()
    if player ~= nil and player.GetCamera ~= nil then
        return player:GetCamera()
    end
    return nil
end

local function is_location_in_player_view_frustum(location)
    local camera = get_player_camera()
    if camera == nil or location == nil or camera.GetLocation == nil then
        return false
    end

    local forward = camera.Forward
    local right = camera.Right
    local up = camera.Up
    if forward == nil or right == nil or up == nil then
        return false
    end

    local diff = location - camera:GetLocation()
    local depth = diff:Dot(forward)
    if depth <= 0.0 then
        return false
    end

    local fov = 1.0471975511965976
    if camera.GetFOV ~= nil then
        fov = tonumber(camera:GetFOV()) or fov
    end

    local aspect = 16.0 / 9.0
    if camera.GetAspectRatio ~= nil then
        aspect = tonumber(camera:GetAspectRatio()) or aspect
    end

    local verticalExtent = math.tan(fov * 0.5) * depth
    local horizontalExtent = verticalExtent * aspect
    return math.abs(diff:Dot(up)) <= verticalExtent and
        math.abs(diff:Dot(right)) <= horizontalExtent
end

local function is_trace_clear_to_actor(startLocation, targetActor, ignoreActor)
    if World == nil or World.LineTraceObjects == nil then
        return false
    end
    if startLocation == nil or not is_valid_actor(targetActor) then
        return false
    end

    local targetLocation = get_trace_location(targetActor)
    if targetLocation == nil then
        return false
    end

    local hit = World.LineTraceObjects(startLocation, targetLocation, ignoreActor)
    if hit == nil or not hit.Hit then
        return true
    end
    return hit.Actor == targetActor
end

local function is_monkey_in_view_frustum()
    if obj == nil or World == nil or World.IsActorInViewFrustum == nil then
        return false
    end
    return World.IsActorInViewFrustum(obj)
end

local function is_monkey_observed_by_player()
    if not is_monkey_in_view_frustum() then
        return false
    end

    local camera = get_player_camera()
    if camera == nil or camera.GetLocation == nil then
        return false
    end

    return is_trace_clear_to_actor(camera:GetLocation(), obj, get_player_pawn())
end

local function face_player_until_observed()
    if bMonkeyAtInitPosition or bObservedSinceTeleport then
        return
    end

    local location = get_actor_location(obj)
    if location ~= nil then
        set_actor_rotation(obj, make_yaw_rotation_to_player(location))
    end
end

local function move_monkey_to_actor(target, rotation)
    if obj == nil or not is_valid_actor(target) then
        return false
    end

    local location = get_actor_location(target)
    if location == nil then
        return false
    end

    local snappedLocation = snap_location_to_floor(location)
    set_actor_location(obj, snappedLocation)
    set_actor_rotation(obj, rotation or Vec3(0.0, 0.0, 0.0))
    bObservedSinceTeleport = false
    return true
end

local function reset_monkey_teleport_position()
    if World == nil or World.FindFirstActorByTag == nil then
        bObservedSinceTeleport = false
        return false
    end

    local initActor = World.FindFirstActorByTag(INIT_POSITION_TAG)
    if not move_monkey_to_actor(initActor, get_actor_rotation(initActor)) then
        bObservedSinceTeleport = false
        return false
    end
    bMonkeyAtInitPosition = true
    return true
end

local function find_nearest_unblocked_candidate()
    if World == nil or World.FindActorsByTag == nil then
        return nil
    end

    local player = get_player_pawn()
    local playerLocation = get_actor_location(player)
    local traceStart = get_trace_location(player) or playerLocation
    if playerLocation == nil then
        return nil
    end

    local candidates = World.FindActorsByTag(POSITION_CANDIDATE_TAG)
    if candidates == nil then
        return nil
    end

    local bestCandidate = nil
    local bestDistance = nil
    for _, candidate in pairs(candidates) do
        if is_valid_actor(candidate) then
            local candidateLocation = get_actor_location(candidate)
            if candidateLocation ~= nil and
                not is_location_in_player_view_frustum(candidateLocation) and
                is_trace_clear_to_actor(traceStart, candidate, player) then
                local distance = (candidateLocation - playerLocation):Length()
                if bestDistance == nil or distance < bestDistance then
                    bestDistance = distance
                    bestCandidate = candidate
                end
            end
        end
    end

    return bestCandidate
end

local function teleport_to_candidate()
    local candidate = find_nearest_unblocked_candidate()
    if candidate == nil then
        return false
    end

    local candidateLocation = snap_location_to_floor(get_actor_location(candidate))
    if move_monkey_to_actor(candidate, make_yaw_rotation_to_player(candidateLocation)) then
        bMonkeyAtInitPosition = false
        return true
    end
    return false
end

local function update_monkey_teleport()
    face_player_until_observed()

    if is_monkey_in_view_frustum() then
        if is_monkey_observed_by_player() then
            bObservedSinceTeleport = true
        end
        return
    end

    if bObservedSinceTeleport then
        teleport_to_candidate()
    end
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
        not is_loop_stopped() and
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

local function get_game_manager_pressure()
    if GameManager.GetPressureStage ~= nil then
        return normalize_pressure(GameManager:GetPressureStage()) or PRESSURE_ENTRY_STRIKE
    end
    return PRESSURE_ENTRY_STRIKE
end

local function handle_pressure_changed(pressure)
    pressure = normalize_pressure(pressure) or PRESSURE_ENTRY_STRIKE

    if is_loop_stopped() then
        CurrentPressure = pressure
        return
    end

    if GameManager:IsPlaying() then
        enter_pressure(pressure)
        return
    end

    CurrentPressure = pressure
end

local function register_pressure_listener()
    if PressureChangedHandle ~= nil then
        GameManager:RemoveListener("PressureChanged", PressureChangedHandle)
        PressureChangedHandle = nil
    end

    if GameManager.OnPressureChanged ~= nil then
        PressureChangedHandle = GameManager:OnPressureChanged(function(pressure)
            handle_pressure_changed(pressure)
        end)
    end
end

local function unregister_pressure_listener()
    if PressureChangedHandle ~= nil then
        GameManager:RemoveListener("PressureChanged", PressureChangedHandle)
        PressureChangedHandle = nil
    end
end

local function handle_loop_rested()
    if not GameManager:IsPlaying() or is_loop_stopped() then
        return false
    end

    reset_monkey_teleport_position()
    CurrentPressure = get_game_manager_pressure()
    return enter_pressure(CurrentPressure)
end

local function register_loop_listeners()
    if LoopStoppedHandle ~= nil then
        GameManager:RemoveListener("LoopStopped", LoopStoppedHandle)
        LoopStoppedHandle = nil
    end
    if LoopRestedHandle ~= nil then
        GameManager:RemoveListener("LoopRested", LoopRestedHandle)
        LoopRestedHandle = nil
    end

    if GameManager.OnLoopStopped ~= nil then
        LoopStoppedHandle = GameManager:OnLoopStopped(function()
            stop_animation()
        end)
    end
    if GameManager.OnLoopRested ~= nil then
        LoopRestedHandle = GameManager:OnLoopRested(function()
            handle_loop_rested()
        end)
    end
end

local function unregister_loop_listeners()
    if LoopStoppedHandle ~= nil then
        GameManager:RemoveListener("LoopStopped", LoopStoppedHandle)
        LoopStoppedHandle = nil
    end
    if LoopRestedHandle ~= nil then
        GameManager:RemoveListener("LoopRested", LoopRestedHandle)
        LoopRestedHandle = nil
    end
end

function SetPressureStage(pressure)
    local rawPressure = pressure
    pressure = normalize_pressure(pressure)
    if pressure == nil then
        print("[CymbalMonkey] Unknown pressure: " .. tostring(rawPressure))
        return false
    end

    if GameManager.SetPressureStageOverride ~= nil then
        return GameManager:SetPressureStageOverride(pressure)
    end

    return enter_pressure(pressure)
end

function ClearPressureStageOverride()
    if GameManager.ClearPressureStageOverride ~= nil then
        return GameManager:ClearPressureStageOverride()
    end

    CurrentPressure = get_game_manager_pressure()
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

function InitializeFromGameManager()
    Mesh = nil
    bMissingMeshLogged = false
    cache_mesh()

    stop_animation()
    reset_monkey_teleport_position()

    CurrentPressure = get_game_manager_pressure()
    CurrentState = STATE_NONE
    CurrentEntryInterval = calculate_entry_interval()
    bAnimationPlaying = false

    if is_loop_stopped() then
        return true
    end

    if GameManager:IsPlaying() then
        print("[CymbalMonkey] InitializeFromGameManager pressure=" .. tostring(CurrentPressure))
        return enter_pressure(CurrentPressure)
    end

    print("[CymbalMonkey] InitializeFromGameManager ignored: GameManager is not playing")
    return false
end

function BeginPlay()
    Mesh = nil
    bMissingMeshLogged = false
    cache_mesh()
    register_pressure_listener()
    register_loop_listeners()

    CurrentPressure = get_game_manager_pressure()
    CurrentState = STATE_NONE
    CurrentEntryInterval = calculate_entry_interval()
    bAnimationPlaying = false
    stop_pressure_one_coroutine()
    reset_monkey_teleport_position()

    if GameManager:IsPlaying() and not is_loop_stopped() then
        enter_pressure(CurrentPressure)
    end
end

function EndPlay()
    unregister_pressure_listener()
    unregister_loop_listeners()
    stop_animation()
    Mesh = nil
    bObservedSinceTeleport = false
    bMonkeyAtInitPosition = true
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

    if is_loop_stopped() then
        if CurrentState ~= STATE_NONE or bAnimationPlaying or EntryCoroutine ~= nil then
            stop_animation()
        end
        return
    end

    update_monkey_teleport()

    local nextPressure = get_game_manager_pressure()
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
