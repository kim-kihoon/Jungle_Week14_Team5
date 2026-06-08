local GameOverMonkey = {}

local COMPONENT_NAME = "GameOverMonkey"
local CYMBALS_MONKEY_TAG = "CymbalsMonkey"
local POST_PROCESS_MATERIAL_PATH = "Content/Material/PostProcess/HorrorPostProcess.uasset"
local ANIMATION_PATH = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_Warning.uasset"
local ANIMATION_LOOPING = false
local ANIMATION_PLAY_RATE = 1.0

local LOOK_AT_SECONDS = 0.1
local REVEAL_DELAY_SECONDS = 0.3
local RISE_SECONDS = 0.15
local RED_VIGNETTE_SECONDS = 2.0
local SQUEEZE_CYCLE_SECONDS = 0.08
local SQUEEZE_MAX_SCALE = 1.5
local CAMERA_SHAKE_MAX_SCALE = 0.0
local CAMERA_SHAKE_PULSE_SECONDS = 0.05
local unpack_args = table.unpack or unpack

local STATE_NONE = "None"
local STATE_LOOK_AT = "LookAt"
local STATE_REVEAL_DELAY = "RevealDelay"
local STATE_RISE = "Rise"
local STATE_RED_VIGNETTE = "RedVignette"
local STATE_FINISHED = "Finished"

GameOverMonkey.PlayerActor = nil
GameOverMonkey.Mesh = nil
GameOverMonkey.State = STATE_NONE
GameOverMonkey.StateElapsed = 0.0
GameOverMonkey.PresentationElapsed = 0.0
GameOverMonkey.OnFinished = nil
GameOverMonkey.ActiveCamera = nil
GameOverMonkey.PlayerPawn = nil
GameOverMonkey.SavedControlRotation = nil
GameOverMonkey.LookStartControlRotation = nil
GameOverMonkey.LookTargetControlRotation = nil
GameOverMonkey.CameraShakeElapsed = 0.0
GameOverMonkey.SqueezeElapsed = 0.0
GameOverMonkey.OriginalScale = nil
GameOverMonkey.OriginalLocalLocation = nil
GameOverMonkey.StartLocalLocation = nil

local function log_failure(message)
    print("[GameOverMonkey] " .. tostring(message))
end

local function clamp01(value)
    value = tonumber(value) or 0.0
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

local function smooth_step(value)
    value = clamp01(value)
    return value * value * (3.0 - 2.0 * value)
end

local function lerp(a, b, alpha)
    return (tonumber(a) or 0.0) + ((tonumber(b) or 0.0) - (tonumber(a) or 0.0)) * alpha
end

local function angle_delta(from, to)
    local delta = ((to - from + 180.0) % 360.0) - 180.0
    return delta
end

local function lerp_angle(from, to, alpha)
    return from + angle_delta(from, to) * alpha
end

local function copy_vec3(value)
    if value == nil then
        return nil
    end

    return Vec3(value.X or 0.0, value.Y or 0.0, value.Z or 0.0)
end

local function make_vec4(x, y, z, w)
    return { X = x, Y = y, Z = z, W = w }
end

local function call_object_function(object, functionName, ...)
    if object == nil or object.CallFunction == nil then
        return false, nil
    end

    local args = { ... }
    local ok, result = pcall(function()
        return object:CallFunction(functionName, unpack_args(args))
    end)
    if not ok then
        return false, result
    end
    return true, result
end

local function atan2(y, x)
    if math.atan2 ~= nil then
        return math.atan2(y, x)
    end
    return math.atan(y, x)
end

local function get_location(object)
    if object == nil or object.GetLocation == nil then
        return nil
    end

    local ok, location = pcall(function()
        return object:GetLocation()
    end)
    if ok then
        return location
    end
    return nil
end

local function get_player_pawn(playerActor)
    if playerActor == nil or playerActor.AsPawn == nil then
        return nil
    end

    local ok, pawn = pcall(function()
        return playerActor:AsPawn()
    end)
    if ok then
        return pawn
    end
    return nil
end

local function get_control_rotation(pawn)
    if pawn == nil or pawn.GetControlRotation == nil then
        return nil
    end

    local ok, rotation = pcall(function()
        return pawn:GetControlRotation()
    end)
    if ok then
        return rotation
    end
    return nil
end

local function set_control_rotation(pawn, rotation)
    if pawn == nil or pawn.SetControlRotation == nil or rotation == nil then
        return false
    end

    local ok = pcall(function()
        pawn:SetControlRotation(rotation)
    end)
    return ok == true
end

local function get_active_camera(playerActor)
    if CameraManager ~= nil and CameraManager.GetActiveCamera ~= nil then
        local ok, camera = pcall(function()
            return CameraManager.GetActiveCamera()
        end)
        if ok and camera ~= nil then
            return camera
        end
    end

    if playerActor ~= nil and playerActor.GetCamera ~= nil then
        local ok, camera = pcall(function()
            return playerActor:GetCamera()
        end)
        if ok then
            return camera
        end
    end

    return nil
end

local function find_first_actor_by_tag(tag)
    if World == nil then
        return nil
    end

    if World.FindFirstActorByTag ~= nil then
        local ok, actor = pcall(function()
            return World.FindFirstActorByTag(tag)
        end)
        if ok and actor ~= nil then
            return actor
        end
    end

    if World.FindActorsByTag ~= nil then
        local ok, actors = pcall(function()
            return World.FindActorsByTag(tag)
        end)
        if ok and actors ~= nil and #actors > 0 then
            return actors[1]
        end
    end

    return nil
end

local function calculate_look_rotation(cameraLocation, targetLocation, baseRotation)
    if cameraLocation == nil or targetLocation == nil or baseRotation == nil then
        return nil
    end

    local dx = (targetLocation.X or 0.0) - (cameraLocation.X or 0.0)
    local dy = (targetLocation.Y or 0.0) - (cameraLocation.Y or 0.0)
    local dz = (targetLocation.Z or 0.0) - (cameraLocation.Z or 0.0)
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length <= 0.0001 then
        return nil
    end

    local invLength = 1.0 / length
    local z = dz * invLength
    if z > 1.0 then
        z = 1.0
    elseif z < -1.0 then
        z = -1.0
    end

    local radToDeg = 180.0 / math.pi
    local pitch = -math.asin(z) * radToDeg
    local yaw = atan2(dy, dx) * radToDeg

    return Vec3(baseRotation.X or 0.0, pitch, yaw)
end

local function lerp_vec3(from, to, alpha)
    if from == nil or to == nil then
        return nil
    end

    return Vec3(
        lerp(from.X or 0.0, to.X or 0.0, alpha),
        lerp(from.Y or 0.0, to.Y or 0.0, alpha),
        lerp(from.Z or 0.0, to.Z or 0.0, alpha)
    )
end

local function multiply_vec3(value, scale)
    if value == nil then
        return nil
    end

    return Vec3(
        (value.X or 0.0) * scale,
        (value.Y or 0.0) * scale,
        (value.Z or 0.0) * scale
    )
end

local function get_relative_location(component)
    if component == nil then
        return nil
    end

    local ok, location = pcall(function()
        return component.RelativeLocation
    end)
    if ok then
        return copy_vec3(location)
    end
    return nil
end

local function set_relative_location(component, location)
    if component == nil or location == nil then
        return false
    end

    local ok = pcall(function()
        component.RelativeLocation = location
    end)
    return ok == true
end

local function set_post_process_scalar(camera, name, value)
    if camera == nil or camera.SetPostProcessScalarParameter == nil then
        return false
    end

    local ok, result = pcall(function()
        return camera:SetPostProcessScalarParameter(name, value)
    end)
    return ok and result ~= false
end

local function set_post_process_vector(camera, name, value)
    if camera == nil or camera.SetPostProcessVectorParameter == nil then
        return false
    end

    local ok, result = pcall(function()
        return camera:SetPostProcessVectorParameter(name, value)
    end)
    return ok and result ~= false
end

local function ensure_horror_post_process(camera)
    if camera == nil or camera.SetPostProcessMaterial == nil then
        return false
    end

    local hasMaterial = false
    if camera.GetPostProcessMaterial ~= nil then
        local ok, material = pcall(function()
            return camera:GetPostProcessMaterial()
        end)
        hasMaterial = ok and material ~= nil
    end

    if hasMaterial then
        return true
    end

    local ok, result = pcall(function()
        return camera:SetPostProcessMaterial(POST_PROCESS_MATERIAL_PATH)
    end)
    return ok and result ~= false
end

local function stop_camera_shake()
    if World == nil or World.GetFirstPlayerController == nil then
        return
    end

    local okController, controller = pcall(function()
        return World.GetFirstPlayerController()
    end)
    if not okController or controller == nil or controller.GetPlayerCameraManager == nil then
        return
    end

    local okManager, manager = pcall(function()
        return controller:GetPlayerCameraManager()
    end)
    if okManager and manager ~= nil and manager.StopAllCameraShakes ~= nil then
        pcall(function()
            manager:StopAllCameraShakes(true)
        end)
    end
end

local function start_camera_shake(scale)
    if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil then
        pcall(function()
            CameraManager.StartWaveShake(scale)
        end)
    end
end

function GameOverMonkey:GetMesh()
    if self.Mesh ~= nil then
        return self.Mesh
    end

    local actor = self.PlayerActor
    if actor == nil then
        log_failure("player actor is nil")
        return nil
    end
    if actor.GetSkeletalMeshComponentByName == nil then
        log_failure("player actor has no GetSkeletalMeshComponentByName")
        return nil
    end

    local ok, componentOrError = pcall(function()
        return actor:GetSkeletalMeshComponentByName(COMPONENT_NAME)
    end)
    if not ok then
        log_failure("GetSkeletalMeshComponentByName failed: " .. tostring(componentOrError))
        return nil
    end

    if componentOrError == nil then
        log_failure("skeletal mesh component not found: " .. COMPONENT_NAME)
        return nil
    end

    self.Mesh = componentOrError
    return self.Mesh
end

function GameOverMonkey:SetVisible(visible)
    local mesh = self:GetMesh()
    if mesh == nil then
        log_failure("SetVisible failed: mesh is nil")
        return false
    end

    if mesh.SetVisibility == nil then
        log_failure("SetVisibility unavailable")
        return false
    end

    local ok, err = pcall(function()
        mesh:SetVisibility(visible == true)
    end)
    if not ok then
        log_failure("SetVisibility failed: " .. tostring(err))
        return false
    end

    return true
end

function GameOverMonkey:GetMeshScale()
    local mesh = self:GetMesh()
    if mesh == nil then
        return nil
    end

    local ok, scale = call_object_function(mesh, "GetRelativeScale")
    if ok and scale ~= nil then
        return copy_vec3(scale)
    end

    return nil
end

function GameOverMonkey:GetMeshLocalLocation()
    local mesh = self:GetMesh()
    if mesh == nil then
        return nil
    end

    return get_relative_location(mesh)
end

function GameOverMonkey:SetMeshLocalLocation(location)
    local mesh = self:GetMesh()
    if mesh == nil or location == nil then
        return false
    end

    if set_relative_location(mesh, location) then
        return true
    end

    log_failure("RelativeLocation unavailable")
    return false
end

function GameOverMonkey:SetMeshScale(scale)
    local mesh = self:GetMesh()
    if mesh == nil or scale == nil then
        return false
    end

    local ok = call_object_function(mesh, "SetRelativeScale", scale)
    if ok then
        return true
    end

    log_failure("SetRelativeScale unavailable")
    return false
end

function GameOverMonkey:ApplySqueeze(dt)
    if self.OriginalScale == nil then
        return false
    end

    self.SqueezeElapsed = (self.SqueezeElapsed + (tonumber(dt) or 0.0)) % SQUEEZE_CYCLE_SECONDS

    local halfCycle = SQUEEZE_CYCLE_SECONDS * 0.5
    local alpha = 0.0
    if self.SqueezeElapsed < halfCycle then
        alpha = self.SqueezeElapsed / halfCycle
    else
        alpha = 1.0 - ((self.SqueezeElapsed - halfCycle) / halfCycle)
    end

    local scaleMultiplier = lerp(1.0, SQUEEZE_MAX_SCALE, smooth_step(alpha))
    return self:SetMeshScale(multiply_vec3(self.OriginalScale, scaleMultiplier))
end

function GameOverMonkey:StopAnimation()
    local mesh = self:GetMesh()
    if mesh == nil then
        return false
    end

    local bStopped = false
    if mesh.StopAnimation ~= nil then
        local ok = pcall(function()
            mesh:StopAnimation()
        end)
        bStopped = bStopped or ok
    end
    if mesh.SetPlaying ~= nil then
        local ok = pcall(function()
            mesh:SetPlaying(false)
        end)
        bStopped = bStopped or ok
    end

    return bStopped
end

function GameOverMonkey:PlayAnimation()
    local mesh = self:GetMesh()
    if mesh == nil then
        log_failure("PlayAnimation failed: mesh is nil")
        return false
    end
    if mesh.PlayAnimationByPath == nil then
        log_failure("PlayAnimation failed: PlayAnimationByPath unavailable")
        return false
    end

    local ok, resultOrError = pcall(function()
        return mesh:PlayAnimationByPath(ANIMATION_PATH, ANIMATION_LOOPING)
    end)

    if not ok then
        log_failure("PlayAnimationByPath failed: " .. tostring(resultOrError))
        return false
    end

    if resultOrError == false then
        log_failure("PlayAnimationByPath returned false: " .. ANIMATION_PATH)
        return false
    end

    if mesh.SetPlayRate ~= nil then
        local rateOk, err = pcall(function()
            mesh:SetPlayRate(ANIMATION_PLAY_RATE)
        end)
        if not rateOk then
            log_failure("SetPlayRate failed: " .. tostring(err))
        end
    end

    return true
end

function GameOverMonkey:ResetPresentationState()
    self.State = STATE_NONE
    self.StateElapsed = 0.0
    self.PresentationElapsed = 0.0
    self.OnFinished = nil
    self.ActiveCamera = nil
    self.PlayerPawn = nil
    self.SavedControlRotation = nil
    self.LookStartControlRotation = nil
    self.LookTargetControlRotation = nil
    self.CameraShakeElapsed = 0.0
    self.SqueezeElapsed = 0.0
    self.StartLocalLocation = nil
end

function GameOverMonkey:ApplyPostProcess(vignetteAlpha, noiseAlpha)
    local camera = self.ActiveCamera or get_active_camera(self.PlayerActor)
    if camera == nil then
        return false
    end

    self.ActiveCamera = camera
    ensure_horror_post_process(camera)

    vignetteAlpha = clamp01(vignetteAlpha)
    noiseAlpha = clamp01(noiseAlpha)

    set_post_process_vector(camera, "VignetteColor", make_vec4(1.0, 0.0, 0.0, vignetteAlpha))
    set_post_process_scalar(camera, "VignetteIntensity", 1.35 * vignetteAlpha)
    set_post_process_scalar(camera, "VignetteRadius", 0.05)
    set_post_process_scalar(camera, "VignetteSoftness", 1.0)
    set_post_process_scalar(camera, "ChromaticStrength", 0.5 * vignetteAlpha)
    set_post_process_scalar(camera, "Time", self.PresentationElapsed)

    if noiseAlpha > 0.0 then
        set_post_process_scalar(camera, "GrainStrength", 3.0 * noiseAlpha)
        set_post_process_scalar(camera, "GrainScale", 1.0)
        set_post_process_scalar(camera, "GrainDarkPower", 0.0)
        set_post_process_scalar(camera, "NoiseMin", 0.0)
        set_post_process_scalar(camera, "NoiseMax", 1.0)
        set_post_process_vector(camera, "NoiseColor", make_vec4(1.0, 1.0, 1.0, noiseAlpha))
    else
        set_post_process_scalar(camera, "GrainStrength", 0.0)
        set_post_process_vector(camera, "NoiseColor", make_vec4(1.0, 1.0, 1.0, 0.0))
    end

    return true
end

function GameOverMonkey:ClearPostProcess()
    local camera = self.ActiveCamera or get_active_camera(self.PlayerActor)
    if camera == nil then
        return false
    end

    ensure_horror_post_process(camera)
    set_post_process_vector(camera, "VignetteColor", make_vec4(0.0, 0.0, 0.0, 0.0))
    set_post_process_scalar(camera, "VignetteIntensity", 0.0)
    set_post_process_scalar(camera, "VignetteRadius", 0.5)
    set_post_process_scalar(camera, "VignetteSoftness", 0.5)
    set_post_process_scalar(camera, "ChromaticStrength", 0.0)
    set_post_process_scalar(camera, "GrainStrength", 0.0)
    set_post_process_scalar(camera, "GrainScale", 1.0)
    set_post_process_scalar(camera, "GrainDarkPower", 0.0)
    set_post_process_scalar(camera, "NoiseMin", 0.0)
    set_post_process_scalar(camera, "NoiseMax", 1.0)
    set_post_process_vector(camera, "NoiseColor", make_vec4(1.0, 1.0, 1.0, 0.0))
    set_post_process_scalar(camera, "Time", 0.0)
    return true
end

function GameOverMonkey:StartLookAtCymbalsMonkey()
    self.State = STATE_LOOK_AT
    self.StateElapsed = 0.0
    self.ActiveCamera = get_active_camera(self.PlayerActor)
    self.PlayerPawn = get_player_pawn(self.PlayerActor)

    local camera = self.ActiveCamera
    local monkey = find_first_actor_by_tag(CYMBALS_MONKEY_TAG)
    if camera == nil or monkey == nil or self.PlayerPawn == nil then
        self:StartRevealDelay()
        return false
    end

    local cameraLocation = get_location(camera)
    local monkeyLocation = get_location(monkey)
    local startControlRotation = get_control_rotation(self.PlayerPawn)
    local targetLookRotation = calculate_look_rotation(cameraLocation, monkeyLocation, startControlRotation)
    if startControlRotation == nil or targetLookRotation == nil then
        self:StartRevealDelay()
        return false
    end

    self.SavedControlRotation = self.SavedControlRotation or copy_vec3(startControlRotation)
    self.LookStartControlRotation = copy_vec3(startControlRotation)
    self.LookTargetControlRotation = Vec3(
        targetLookRotation.X or 0.0,
        targetLookRotation.Y or 0.0,
        targetLookRotation.Z or 0.0
    )
    return true
end

function GameOverMonkey:TickLookAtCymbalsMonkey(dt)
    self.StateElapsed = self.StateElapsed + dt
    local alpha = smooth_step(self.StateElapsed / LOOK_AT_SECONDS)

    if self.PlayerPawn ~= nil
        and self.LookStartControlRotation ~= nil
        and self.LookTargetControlRotation ~= nil then
        set_control_rotation(self.PlayerPawn, Vec3(
            lerp_angle(self.LookStartControlRotation.X or 0.0, self.LookTargetControlRotation.X or 0.0, alpha),
            lerp_angle(self.LookStartControlRotation.Y or 0.0, self.LookTargetControlRotation.Y or 0.0, alpha),
            lerp_angle(self.LookStartControlRotation.Z or 0.0, self.LookTargetControlRotation.Z or 0.0, alpha)
        ))
    end

    if self.StateElapsed >= LOOK_AT_SECONDS then
        if self.PlayerPawn ~= nil and self.LookTargetControlRotation ~= nil then
            set_control_rotation(self.PlayerPawn, self.LookTargetControlRotation)
        end
        self:StartRevealDelay()
    end
end

function GameOverMonkey:StartRevealDelay()
    self.State = STATE_REVEAL_DELAY
    self.StateElapsed = 0.0
end

function GameOverMonkey:TickRevealDelay(dt)
    self.StateElapsed = self.StateElapsed + dt
    if self.StateElapsed >= REVEAL_DELAY_SECONDS then
        self:StartRiseMonkey()
    end
end

function GameOverMonkey:StartRiseMonkey()
    self.State = STATE_RISE
    self.StateElapsed = 0.0

    local originalLocation = self.OriginalLocalLocation or self:GetMeshLocalLocation()
    if originalLocation == nil then
        log_failure("StartRiseMonkey failed: original local location is nil")
        self:StartRedVignetteAndShake()
        return false
    end

    self.OriginalLocalLocation = copy_vec3(originalLocation)
    self.StartLocalLocation = Vec3(
        self.OriginalLocalLocation.X or 0.0,
        self.OriginalLocalLocation.Y or 0.0,
        (self.OriginalLocalLocation.Z or 0.0) - 1.0
    )
    self:SetMeshLocalLocation(self.StartLocalLocation)
    self:SetVisible(true)
    return true
end

function GameOverMonkey:TickRiseMonkey(dt)
    self.StateElapsed = self.StateElapsed + dt
    local alpha = smooth_step(self.StateElapsed / RISE_SECONDS)
    local location = lerp_vec3(self.StartLocalLocation, self.OriginalLocalLocation, alpha)
    self:SetMeshLocalLocation(location)

    if self.StateElapsed >= RISE_SECONDS then
        self:SetMeshLocalLocation(self.OriginalLocalLocation)
        self:StartRedVignetteAndShake()
    end
end

function GameOverMonkey:StartRedVignetteAndShake()
    self.State = STATE_RED_VIGNETTE
    self.StateElapsed = 0.0
    self.CameraShakeElapsed = CAMERA_SHAKE_PULSE_SECONDS
    self.SqueezeElapsed = 0.0
    self:PlayAnimation()
    self:ApplyPostProcess(0.0, 0.0)
end

function GameOverMonkey:TickRedVignetteAndShake(dt)
    self.StateElapsed = self.StateElapsed + dt
    local alpha = smooth_step(self.StateElapsed / RED_VIGNETTE_SECONDS)
    self:ApplyPostProcess(alpha, 0.0)
    self:ApplySqueeze(dt)

    self.CameraShakeElapsed = self.CameraShakeElapsed + dt
    if self.CameraShakeElapsed >= CAMERA_SHAKE_PULSE_SECONDS then
        self.CameraShakeElapsed = 0.0
        start_camera_shake(CAMERA_SHAKE_MAX_SCALE)
    end

    if self.StateElapsed >= RED_VIGNETTE_SECONDS then
        self:StartNoiseAndMenu()
    end
end

function GameOverMonkey:StartNoiseAndMenu()
    self.State = STATE_FINISHED
    self.StateElapsed = 0.0
    stop_camera_shake()
    self:SetMeshScale(self.OriginalScale)
    self:ApplyPostProcess(1.0, 1.0)

    local callback = self.OnFinished
    self.OnFinished = nil
    if callback ~= nil then
        pcall(callback)
    end
end

function GameOverMonkey:StartPresentation(onFinished)
    self:ClearPresentation()
    self.OnFinished = onFinished
    self.OriginalScale = self:GetMeshScale()
    self.OriginalLocalLocation = self:GetMeshLocalLocation()
    self.ActiveCamera = get_active_camera(self.PlayerActor)
    self.PlayerPawn = get_player_pawn(self.PlayerActor)
    self.SavedControlRotation = copy_vec3(get_control_rotation(self.PlayerPawn))
    self:StartLookAtCymbalsMonkey()
    return true
end

function GameOverMonkey:Tick(dt)
    if self.State == STATE_NONE or self.State == STATE_FINISHED then
        return
    end

    dt = tonumber(dt) or 0.0
    if dt < 0.0 then
        dt = 0.0
    end
    self.PresentationElapsed = self.PresentationElapsed + dt

    if self.State == STATE_LOOK_AT then
        self:TickLookAtCymbalsMonkey(dt)
    elseif self.State == STATE_REVEAL_DELAY then
        self:TickRevealDelay(dt)
    elseif self.State == STATE_RISE then
        self:TickRiseMonkey(dt)
    elseif self.State == STATE_RED_VIGNETTE then
        self:TickRedVignetteAndShake(dt)
    end
end

function GameOverMonkey:PlayPresentationAnimation()
    return self:StartPresentation(nil)
end

function GameOverMonkey:Hide()
    self:StopAnimation()
    self:SetMeshScale(self.OriginalScale)
    self:SetMeshLocalLocation(self.OriginalLocalLocation)
    return self:SetVisible(false)
end

function GameOverMonkey:ClearPresentation()
    local savedControlRotation = self.SavedControlRotation
    local pawn = self.PlayerPawn

    self:StopAnimation()
    if self.OriginalScale ~= nil then
        self:SetMeshScale(self.OriginalScale)
    end
    if self.OriginalLocalLocation ~= nil then
        self:SetMeshLocalLocation(self.OriginalLocalLocation)
    end
    self:SetVisible(false)
    self:ClearPostProcess()
    stop_camera_shake()

    if savedControlRotation ~= nil then
        set_control_rotation(pawn, savedControlRotation)
    end

    self:ResetPresentationState()
    return true
end

function GameOverMonkey:Initialize(playerActor)
    self.PlayerActor = playerActor
    self.Mesh = nil
    self.OriginalScale = self:GetMeshScale()
    self.OriginalLocalLocation = self:GetMeshLocalLocation()
    self:ClearPresentation()
end

function GameOverMonkey:Shutdown()
    self:ClearPresentation()
    self.PlayerActor = nil
    self.Mesh = nil
    self.OriginalScale = nil
    self.OriginalLocalLocation = nil
    self.SavedControlRotation = nil
end

return GameOverMonkey
