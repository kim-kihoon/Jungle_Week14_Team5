-- Hospital.Scene 플레이어 흐름과 씬 상호작용을 연결한다.

local GameManager = require("GameManager")
local DoorManager = require("DoorManager")
local SoundManager = require("SoundManager")
local UIManager = require("UIManager")
local ToolManager = require("ToolManager")

local TRIGGER_Y_MIN = 27.132
local TRIGGER_X_MAX = -3.0
local WARP_DELTA_X = 8.368179
local WARP_DELTA_Y = -33.80393
local WARP_DELTA_Z = 0.0

local bCanWarp = true
local bLastLoopStopped = false
local bTitleMode = true

local KEY_W = 0x57
local KEY_A = 0x41
local KEY_S = 0x53
local KEY_D = 0x44
local TITLE_CAMERA_TAG = "TitleCamera"
local TITLE_ACTOR_TAG = "Title"
local TITLE_MONKEY_ACTOR_NAME = "TitleMonkey"
local TITLE_MONKEY_START_FUNCTION = "PlayStartAnimation"
local TITLE_FADE_OUT_SECONDS = 0.75
local TITLE_BLACK_HOLD_SECONDS = 0.1
local TITLE_FADE_IN_SECONDS = 0.75

local bTitleTransitioning = false
local TitleTransitionCoroutine = nil
local TitleTransitionWaitRemaining = 0.0

local function IsInTriggerZone(location)
    return location.Y > TRIGGER_Y_MIN and location.X < TRIGGER_X_MAX
end

local function IsKeyDown(key)
    if Input == nil or Input.GetKey == nil then
        return false
    end

    local ok, down = pcall(function()
        return Input.GetKey(key)
    end)
    return ok and down == true
end

local function GetInputAxis(name)
    if Input == nil or Input.GetAxis == nil then
        return 0.0
    end

    local ok, value = pcall(function()
        return Input.GetAxis(name)
    end)
    if ok and value ~= nil then
        return value
    end
    return 0.0
end

local function GetActionDown(name)
    if Input == nil or Input.GetActionDown == nil then
        return false
    end

    local ok, pressed = pcall(function()
        return Input.GetActionDown(name)
    end)
    return ok and pressed == true
end

local function IsLoopStopped()
    return GameManager ~= nil
        and GameManager.IsLoopStopped ~= nil
        and GameManager:IsLoopStopped()
end

local function AddPlayerMovement()
    if obj == nil then
        return
    end

    local forwardInput = GetInputAxis("MoveForward")
    local rightInput = GetInputAxis("MoveRight")
    if forwardInput == 0.0 and rightInput == 0.0 then
        if IsKeyDown(KEY_W) then forwardInput = forwardInput + 1.0 end
        if IsKeyDown(KEY_S) then forwardInput = forwardInput - 1.0 end
        if IsKeyDown(KEY_D) then rightInput = rightInput + 1.0 end
        if IsKeyDown(KEY_A) then rightInput = rightInput - 1.0 end
    end

    if forwardInput == 0.0 and rightInput == 0.0 then
        return
    end

    local forward = Vec3(1.0, 0.0, 0.0)
    local right = Vec3(0.0, 1.0, 0.0)

    local okForward, actorForward = pcall(function()
        return obj.Forward
    end)
    if okForward and actorForward ~= nil then
        forward = Vec3(actorForward.X, actorForward.Y, 0.0)
    end

    local okRight, actorRight = pcall(function()
        return obj.Right
    end)
    if okRight and actorRight ~= nil then
        right = Vec3(actorRight.X, actorRight.Y, 0.0)
    end

    if forwardInput ~= 0.0 then
        pcall(function()
            obj:AddMovementInput(forward, forwardInput)
        end)
    end
    if rightInput ~= 0.0 then
        pcall(function()
            obj:AddMovementInput(right, rightInput)
        end)
    end
end

local function GetActorCamera(actor)
    if actor == nil then
        return nil
    end

    local ok, camera = pcall(function()
        return actor:GetCamera()
    end)
    if ok then
        return camera
    end
    return nil
end

local function FindActorByName(name)
    if World == nil or World.FindActorByName == nil then
        return nil
    end

    local ok, actor = pcall(function()
        return World.FindActorByName(name)
    end)
    if ok then
        return actor
    end
    return nil
end

local function FindFirstActorByTag(tag)
    if World == nil or World.FindFirstActorByTag == nil then
        return nil
    end

    local ok, actor = pcall(function()
        return World.FindFirstActorByTag(tag)
    end)
    if ok then
        return actor
    end
    return nil
end

local function SetActiveCameraImmediate(camera)
    if camera == nil or CameraManager == nil then
        return false
    end

    if CameraManager.PossessCamera ~= nil then
        local ok, result = pcall(function()
            return CameraManager.PossessCamera(camera)
        end)
        if ok then
            return result ~= false
        end
    end

    if CameraManager.SetActiveCamera ~= nil then
        local ok = pcall(function()
            CameraManager.SetActiveCamera(camera)
        end)
        return ok
    end

    return false
end

local function PlayCameraFadeOut(duration)
    if CameraManager == nil or CameraManager.FadeOut == nil then
        return false
    end

    local ok = pcall(function()
        CameraManager.FadeOut(duration)
    end)
    return ok == true
end

local function PlayCameraFadeIn(duration)
    if CameraManager == nil or CameraManager.FadeIn == nil then
        return false
    end

    local ok = pcall(function()
        CameraManager.FadeIn(duration)
    end)
    return ok == true
end

local function CaptureTitleCamera()
    local titleCameraActor = FindFirstActorByTag(TITLE_CAMERA_TAG) or FindActorByName("Camera")
    return SetActiveCameraImmediate(GetActorCamera(titleCameraActor))
end

local function CapturePlayerCamera()
    local camera = GetActorCamera(obj)
    if camera == nil then
        camera = GetActorCamera(FindActorByName("Player"))
    end
    return SetActiveCameraImmediate(camera)
end

local function DeactivateComponent(component)
    if component == nil then
        return
    end

    pcall(function()
        component:SetVisibility(false)
    end)
    pcall(function()
        component:SetVisible(false)
    end)
    pcall(function()
        component:SetActive(false)
    end)
    pcall(function()
        component:Deactivate()
    end)
end

local function DeactivateTitleActor(actor)
    if actor == nil then
        return
    end

    pcall(function()
        actor:SetVisible(false)
    end)

    local okComponents, components = pcall(function()
        return actor:GetComponents()
    end)
    if okComponents and components ~= nil then
        for _, component in ipairs(components) do
            DeactivateComponent(component)
        end
        return
    end

    local okRoot, root = pcall(function()
        return actor:GetRootPrimitiveComponent()
    end)
    if okRoot then
        DeactivateComponent(root)
    end
end

local function DeactivateTitleActors()
    if World == nil or World.FindActorsByTag == nil then
        return
    end

    local ok, actors = pcall(function()
        return World.FindActorsByTag(TITLE_ACTOR_TAG)
    end)
    if not ok or actors == nil then
        return
    end

    for _, actor in ipairs(actors) do
        DeactivateTitleActor(actor)
    end
end

local function PlayTitleMonkeyStartAnimation()
    local titleMonkey = FindActorByName(TITLE_MONKEY_ACTOR_NAME)
    if titleMonkey == nil or titleMonkey.GetLuaScriptComponent == nil then
        return false
    end

    local luaScript = titleMonkey:GetLuaScriptComponent()
    if luaScript == nil or luaScript.CallFunction == nil then
        return false
    end

    local ok, result = pcall(function()
        return luaScript:CallFunction(TITLE_MONKEY_START_FUNCTION)
    end)
    return ok and result ~= false
end

local function StopTitleTransitionCoroutine()
    TitleTransitionCoroutine = nil
    TitleTransitionWaitRemaining = 0.0
    bTitleTransitioning = false
end

local function ApplyGameplayStart()
    bTitleMode = false
    bLastLoopStopped = IsLoopStopped()
    SoundManager:EnterPlayingState()
    if HospitalPlayer ~= nil then
        HospitalPlayer.title_mode = false
    end
    UIManager:DisposeTitle()
    CapturePlayerCamera()
    DeactivateTitleActors()
end

local function WaitTitleTransition(seconds)
    coroutine.yield(tonumber(seconds) or 0.0)
end

local function ResumeTitleTransition(dt)
    if TitleTransitionCoroutine == nil then
        return
    end

    if coroutine.status(TitleTransitionCoroutine) == "dead" then
        StopTitleTransitionCoroutine()
        return
    end

    TitleTransitionWaitRemaining = TitleTransitionWaitRemaining - (tonumber(dt) or 0.0)
    if TitleTransitionWaitRemaining > 0.0 then
        return
    end

    local ok, waitSeconds = coroutine.resume(TitleTransitionCoroutine)
    if not ok then
        StopTitleTransitionCoroutine()
        return
    end

    if coroutine.status(TitleTransitionCoroutine) == "dead" then
        StopTitleTransitionCoroutine()
        return
    end

    TitleTransitionWaitRemaining = math.max(0.0, tonumber(waitSeconds) or 0.0)
end

local function StartTitleTransitionCoroutine()
    TitleTransitionWaitRemaining = 0.0
    TitleTransitionCoroutine = coroutine.create(function()
        PlayCameraFadeOut(TITLE_FADE_OUT_SECONDS)
        WaitTitleTransition(TITLE_FADE_OUT_SECONDS)
        WaitTitleTransition(TITLE_BLACK_HOLD_SECONDS)

        ApplyGameplayStart()

        PlayCameraFadeIn(TITLE_FADE_IN_SECONDS)
        WaitTitleTransition(TITLE_FADE_IN_SECONDS)
    end)

    ResumeTitleTransition(0.0)
end

function BeginPlay()
    StopTitleTransitionCoroutine()
    bCanWarp = true
    bLastLoopStopped = IsLoopStopped()
    bTitleMode = true
    DoorManager:Reset()
    SoundManager:EnterTitleState()
    ToolManager:Reset()
    UIManager:ResetHospital()
    if HospitalPlayer ~= nil then
        HospitalPlayer.title_mode = true
    end
    UIManager:ShowTitle()
    CaptureTitleCamera()
end

function EndPlay()
    StopTitleTransitionCoroutine()
    bCanWarp = true
    bLastLoopStopped = false
    DoorManager:Reset()
    ToolManager:Reset()
    UIManager:ResetHospital()
    bTitleMode = true
    if HospitalPlayer ~= nil then
        HospitalPlayer.title_mode = true
    end
end

function Tick(dt)
    if obj == nil then
        return
    end

    if bTitleTransitioning then
        ResumeTitleTransition(dt)
        if bTitleMode then
            CaptureTitleCamera()
        end
        return
    end

    if bTitleMode then
        CaptureTitleCamera()
        return
    end

    DoorManager:InitDoors()

    local location = obj:GetLocation()
    local bInZone = IsInTriggerZone(location)

    AddPlayerMovement()
    DoorManager:Tick(dt, obj, location)

    local bLoopStopped = IsLoopStopped()
    if bLoopStopped and not bLastLoopStopped then
        DoorManager:OpenExitDoorsForCurrentLoop()
    end
    bLastLoopStopped = bLoopStopped

    if bInZone and bCanWarp then
        obj:AddWorldOffset(Vec3(WARP_DELTA_X, WARP_DELTA_Y, WARP_DELTA_Z))
        GameManager:OnWarp("PlayerWarp")
        bLastLoopStopped = IsLoopStopped()
        DoorManager:LockExitDoorsForCurrentLoop()
        DoorManager:RandomizeSingleDoorStatesOnWarp()
        DoorManager:ClearToyProjectiles()
        bCanWarp = false
    elseif not bInZone then
        bCanWarp = true
    end

    UIManager:UpdateControlPrompt()
    UIManager:UpdateTimerPrompt(GameManager)

    local targetedDoor = DoorManager:FindTargetedDoor(obj)
    UIManager:UpdateDoorPrompt(targetedDoor)

    local bInteractPressed = GetActionDown("Interact")
    if bInteractPressed and targetedDoor ~= nil then
        DoorManager:ToggleDoor(targetedDoor)
        UIManager:UpdateDoorPrompt(targetedDoor)
    end
end

function OnOverlap(OtherActor)
end

function StartGame()
    if not bTitleMode or bTitleTransitioning then
        return
    end

    bTitleTransitioning = true
    UIManager:CloseTitlePopup()
    PlayTitleMonkeyStartAnimation()
    StartTitleTransitionCoroutine()
end

function ShowSetting()
    if not bTitleMode or bTitleTransitioning then
        return false
    end
    UIManager:ShowTitleSetting()
end

function ShowCredit()
    if not bTitleMode or bTitleTransitioning then
        return false
    end
    UIManager:ShowTitleCredit()
end

function ClosePopup()
    UIManager:CloseTitlePopup()
end

function ExitGame()
    if Engine ~= nil and Engine.Exit ~= nil then
        Engine.Exit()
    end
end
