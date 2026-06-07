-- Hospital.Scene 플레이어 루프: 지정 위치에 들어오면 고정 오프셋으로 워프한다.

local GameManager = require("GameManager")

local TRIGGER_Y_MIN = 27.132
local TRIGGER_X_MAX = -3.0
local AUTO_CLOSE_DOOR_TRIGGER_X_MAX = -0.603
local AUTO_CLOSE_DOOR_TRIGGER_Y_MIN = 27.119
local WARP_DELTA_X = 8.368179
local WARP_DELTA_Y = -33.80393
local WARP_DELTA_Z = 0.0

local bCanWarp = true
local Doors = {}
local DoorStateByName = {}
local PendingDoorCloseSounds = {}
local bDoorsInitialized = false
local bInteractWasDown = false
local DoorPromptWidget = nil
local bDoorPromptVisible = false

local INTERACT_KEY = 0x45 -- E
local KEY_W = 0x57
local KEY_A = 0x41
local KEY_S = 0x53
local KEY_D = 0x44
local INTERACT_DISTANCE = 1.0
local INTERACT_DISTANCE_SQ = INTERACT_DISTANCE * INTERACT_DISTANCE
local DOOR_OPEN_DURATION = 1.0
local DOOR_OPEN_ANGLE_PLUS = 80.0
local DOOR_OPEN_ANGLE_MINUS = -80.0
local DOOR_CLOSE_SOUND_DELAY = 1.0
local DOOR_OPEN_SOUND_KEY = "DoorOpen"
local HEAVY_DOOR_OPEN_SOUND_KEY = "HeavyDoorOpen"
local DOOR_CLOSE_SOUND_KEY = "DoorClose"
local DOOR_SOUND_MIN_DISTANCE = 1.0
local DOOR_SOUND_MAX_DISTANCE = 12.0
local DOOR_SOUND_VOLUME = 0.45
local DOOR_OPEN_SOUND_VOLUME = 0.7
local DOOR_CONTACT_SLOP = 0.08
local DOOR_CONTACT_RAY_COUNT = 16
local DOOR_APPROACH_DOT_THRESHOLD = 1.0e-6
local DOOR_PROMPT_DOCUMENT_PATH = "Content/UI/HospitalDoorPrompt.rml"
local DOOR_PROMPT_ELEMENT_ID = "door_prompt"

local OPEN_PLUS_NAMES = {
    AStaticMeshActor_2 = true,
    AStaticMeshActor_2_Copy = true,
    AStaticMeshActor_4_Copy = true,
    AStaticMeshActor_23_Copy = true,
    AStaticMeshActor_24_Copy = true,
    AStaticMeshActor_13 = true,
    AStaticMeshActor_17 = true,
}

local OPEN_MINUS_NAMES = {
    AStaticMeshActor_12 = true,
    AStaticMeshActor_3 = true,
    AStaticMeshActor_4 = true,
    AStaticMeshActor_23 = true,
    AStaticMeshActor_24 = true,
    AStaticMeshActor_16 = true,
}

local INITIALLY_OPEN_NAMES = {
    AStaticMeshActor_3 = true,
    AStaticMeshActor_4_Copy = true,
    AStaticMeshActor_24 = true,
}

local DOUBLE_DOOR_NAMES = {
    AStaticMeshActor_12 = true,
    AStaticMeshActor_13 = true,
    AStaticMeshActor_16 = true,
    AStaticMeshActor_17 = true,
}

local AUTO_CLOSE_DOOR_NAMES = {
    AStaticMeshActor_16 = true,
    AStaticMeshActor_17 = true,
}

local AUTO_CLOSE_Y_DOOR_TRIGGER_Y_MIN = -2.0

local AUTO_CLOSE_Y_DOOR_NAMES = {
    AStaticMeshActor_12 = true,
    AStaticMeshActor_13 = true,
}

local MAX_OPEN_SINGLE_DOORS_ON_WARP = 5
local TOY_PROJECTILE_TAG = "ToyProjectile"

local function IsInTriggerZone(location)
    return location.Y > TRIGGER_Y_MIN and location.X < TRIGGER_X_MAX
end

local function IsInAutoCloseDoorZone(location)
    return location.X < AUTO_CLOSE_DOOR_TRIGGER_X_MAX and location.Y > AUTO_CLOSE_DOOR_TRIGGER_Y_MIN
end

local function IsInAutoCloseYDoorZone(location)
    return location.Y > AUTO_CLOSE_Y_DOOR_TRIGGER_Y_MIN
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

local function AddPlayerMovement()
    if obj == nil then
        return
    end

    local forwardInput = 0.0
    local rightInput = 0.0
    if IsKeyDown(KEY_W) then forwardInput = forwardInput + 1.0 end
    if IsKeyDown(KEY_S) then forwardInput = forwardInput - 1.0 end
    if IsKeyDown(KEY_D) then rightInput = rightInput + 1.0 end
    if IsKeyDown(KEY_A) then rightInput = rightInput - 1.0 end

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

local function ActorName(actor)
    if actor == nil then
        return ""
    end

    local ok, name = pcall(function()
        return actor:GetName()
    end)
    if not ok or name == nil then
        return ""
    end
    return name
end

local function GetActorYaw(actor)
    if actor == nil then
        return 0.0
    end

    local okRoot, root = pcall(function()
        return actor:GetRootPrimitiveComponent()
    end)
    if okRoot and root ~= nil then
        local okRot, rotation = pcall(function()
            return root:GetRotation()
        end)
        if okRot and rotation ~= nil and rotation.Z ~= nil then
            return rotation.Z
        end
    end

    local okRot, rotation = pcall(function()
        return actor.Rotation
    end)
    if okRot and rotation ~= nil and rotation.Z ~= nil then
        return rotation.Z
    end

    return 0.0
end

local function SyncDoorPhysics(actor)
    if actor == nil then
        return
    end

    local ok, root = pcall(function()
        return actor:GetRootPrimitiveComponent()
    end)
    if not ok or root == nil then
        return
    end

    pcall(function()
        root:SyncPhysicsTransform()
    end)
end

local function SetDoorYaw(door, yaw)
    if door == nil or door.Actor == nil then
        return false
    end

    local rotation = Vec3(0.0, 0.0, yaw)
    local actor = door.Actor

    local ok = pcall(function()
        actor.Rotation = rotation
    end)
    if not ok then
        ok = pcall(function()
            actor:SetRotation(rotation)
        end)
    end

    local okRoot, root = pcall(function()
        return actor:GetRootPrimitiveComponent()
    end)
    if okRoot and root ~= nil then
        pcall(function()
            root:SetRotation(rotation)
        end)
    end

    if ok then
        door.CurrentYaw = yaw
    end
    return ok
end

local function SmoothStep(alpha)
    alpha = math.max(0.0, math.min(alpha, 1.0))
    return alpha * alpha * (3.0 - 2.0 * alpha)
end

local function SyncPlayerPhysics()
    if obj == nil then
        return
    end

    local okRoot, root = pcall(function()
        return obj:GetRootPrimitiveComponent()
    end)
    if okRoot and root ~= nil then
        pcall(function()
            root:SyncPhysicsTransform()
        end)
    end
end

local function PlayDoorAudioAt(doorActor, key, volume)
    if doorActor == nil or key == nil then
        return
    end

    volume = tonumber(volume) or DOOR_SOUND_VOLUME

    local okLocation, doorLocation = pcall(function()
        return doorActor:GetLocation()
    end)
    if not okLocation or doorLocation == nil then
        return
    end

    if Audio ~= nil and Audio.PlayAt ~= nil then
        pcall(function()
            Audio.PlayAt(
                key,
                volume,
                doorLocation,
                DOOR_SOUND_MIN_DISTANCE,
                DOOR_SOUND_MAX_DISTANCE
            )
        end)
        return
    end

    if Audio ~= nil and Audio.Play ~= nil then
        pcall(function()
            Audio.Play(key, volume)
        end)
    end
end

local function QueueDoorCloseSound(doorActor)
    if doorActor == nil then
        return
    end

    table.insert(PendingDoorCloseSounds, {
        Delay = DOOR_CLOSE_SOUND_DELAY,
        Actor = doorActor,
    })
end

local function UpdatePendingDoorCloseSounds(dt)
    local deltaTime = tonumber(dt) or 0.0
    if deltaTime <= 0.0 then
        return
    end

    local index = 1
    while index <= #PendingDoorCloseSounds do
        local pending = PendingDoorCloseSounds[index]
        pending.Delay = pending.Delay - deltaTime
        if pending.Delay <= 0.0 then
            PlayDoorAudioAt(pending.Actor, DOOR_CLOSE_SOUND_KEY, DOOR_SOUND_VOLUME)
            table.remove(PendingDoorCloseSounds, index)
        else
            index = index + 1
        end
    end
end

local function GetPlayerCapsuleRadius()
    local okCapsule, capsule = pcall(function()
        return obj:GetCapsuleComponent()
    end)
    if okCapsule and capsule ~= nil then
        local okRadius, radius = pcall(function()
            return capsule:GetScaledCapsuleRadius()
        end)
        if okRadius and radius ~= nil and radius > 0.0 then
            return radius
        end
    end
    return 0.213333
end

local function GetPlayerDoorContact(doorActor)
    if World == nil or World.LineTraceObjects == nil or obj == nil or doorActor == nil then
        return false, nil, nil
    end

    local okPlayerLoc, playerLoc = pcall(function()
        return obj:GetLocation()
    end)
    if not okPlayerLoc or playerLoc == nil then
        return false, nil, nil
    end

    local radius = GetPlayerCapsuleRadius()
    local probeDistance = radius + DOOR_CONTACT_SLOP
    local twoPi = math.pi * 2.0
    local bestDistance = probeDistance + 1.0
    local bestLocation = nil
    local bestNormal = nil

    for rayIndex = 0, DOOR_CONTACT_RAY_COUNT - 1 do
        local angle = (rayIndex / DOOR_CONTACT_RAY_COUNT) * twoPi
        local dirX = math.cos(angle)
        local dirY = math.sin(angle)
        local endPos = Vec3(
            playerLoc.X + dirX * probeDistance,
            playerLoc.Y + dirY * probeDistance,
            playerLoc.Z
        )

        local okHit, hit = pcall(function()
            return World.LineTraceObjects(playerLoc, endPos, obj)
        end)
        if okHit and hit ~= nil and hit.Hit == true and hit.Actor == doorActor then
            local hitDistance = tonumber(hit.Distance) or probeDistance
            if hitDistance <= probeDistance and hitDistance < bestDistance then
                bestDistance = hitDistance
                bestLocation = hit.Location
                bestNormal = hit.Normal
            end
        end
    end

    if bestLocation == nil or bestNormal == nil then
        return false, nil, nil
    end

    return true, bestLocation, bestNormal
end

-- Door panel velocity at the contact point (rigid rotation about hinge).
-- Push only when that velocity points into the player along the contact normal.
local function IsDoorApproachingPlayer(doorActor, yawDelta, contactLocation, contactNormal)
    if doorActor == nil or contactLocation == nil or contactNormal == nil then
        return false
    end
    if math.abs(yawDelta) < 0.001 then
        return false
    end

    local okDoorLoc, doorLoc = pcall(function()
        return doorActor:GetLocation()
    end)
    if not okDoorLoc or doorLoc == nil then
        return false
    end

    local rx = contactLocation.X - doorLoc.X
    local ry = contactLocation.Y - doorLoc.Y
    local yawDeltaRad = math.rad(yawDelta)
    local velX = -yawDeltaRad * ry
    local velY = yawDeltaRad * rx
    local approachDot = velX * contactNormal.X + velY * contactNormal.Y

    return approachDot > DOOR_APPROACH_DOT_THRESHOLD
end

-- Static door bodies teleport in PhysX and do not push kinematic player capsules.
-- Once contact begins during a swing, keep pushing until that swing finishes.
local function PushPlayerFromDoorHinge(doorActor, prevYaw, newYaw)
    if obj == nil or doorActor == nil then
        return
    end

    local yawDelta = newYaw - prevYaw
    if math.abs(yawDelta) < 0.001 then
        return
    end

    local okPlayerLoc, playerLoc = pcall(function()
        return obj:GetLocation()
    end)
    local okDoorLoc, doorLoc = pcall(function()
        return doorActor:GetLocation()
    end)
    if not okPlayerLoc or not okDoorLoc or playerLoc == nil or doorLoc == nil then
        return
    end

    local dx = playerLoc.X - doorLoc.X
    local dy = playerLoc.Y - doorLoc.Y
    if dx * dx + dy * dy < 0.0001 then
        return
    end

    local rad = math.rad(yawDelta)
    local cosA = math.cos(rad)
    local sinA = math.sin(rad)
    local newDx = dx * cosA - dy * sinA
    local newDy = dx * sinA + dy * cosA
    local pushX = newDx - dx
    local pushY = newDy - dy

    if pushX * pushX + pushY * pushY < 1.0e-8 then
        return
    end

    pcall(function()
        obj:AddWorldOffset(Vec3(pushX, pushY, 0.0))
    end)
    SyncPlayerPhysics()
end

local function UpdateDoors(dt)
    local deltaTime = tonumber(dt) or 0.0
    if deltaTime <= 0.0 then
        return
    end

    for _, door in ipairs(Doors) do
        if door.Elapsed < DOOR_OPEN_DURATION then
            door.Elapsed = math.min(door.Elapsed + deltaTime, DOOR_OPEN_DURATION)
            local alpha = SmoothStep(door.Elapsed / DOOR_OPEN_DURATION)
            local prevYaw = door.CurrentYaw
            local nextYaw = door.StartYaw + (door.TargetYaw - door.StartYaw) * alpha
            if SetDoorYaw(door, nextYaw) then
                SyncDoorPhysics(door.Actor)

                local yawDelta = nextYaw - prevYaw
                local touching, contactLocation, contactNormal = GetPlayerDoorContact(door.Actor)
                local approaching = touching and IsDoorApproachingPlayer(
                    door.Actor, yawDelta, contactLocation, contactNormal
                )

                if touching and approaching then
                    door.bPushPlayer = true
                elseif not approaching then
                    door.bPushPlayer = false
                end
                if door.bPushPlayer and approaching then
                    PushPlayerFromDoorHinge(door.Actor, prevYaw, nextYaw)
                end
            end

            if door.Elapsed >= DOOR_OPEN_DURATION then
                door.bPushPlayer = false
            end
        end
    end
end

local function FindDoorByName(name)
    if name == nil or name == "" then
        return nil
    end

    for _, door in ipairs(Doors) do
        if door.Name == name then
            return door
        end
    end

    return nil
end

local function IsSingleDoor(door)
    return door ~= nil and DOUBLE_DOOR_NAMES[door.Name] ~= true
end

local function SetDoorOpenState(door, bOpen, bPlaySound)
    if door == nil or door.Actor == nil or door.IsOpen == bOpen then
        return
    end

    local bWasOpen = door.IsOpen
    door.IsOpen = bOpen
    DoorStateByName[door.Name] = bOpen
    door.StartYaw = door.CurrentYaw
    door.TargetYaw = bOpen and door.OpenYaw or door.CloseYaw
    door.Elapsed = 0.0
    door.bPushPlayer = false

    SetDoorYaw(door, door.StartYaw)
    SyncDoorPhysics(door.Actor)

    if not bPlaySound then
        return
    end

    if bOpen then
        local openVolume = door.OpenSoundKey == DOOR_OPEN_SOUND_KEY and DOOR_OPEN_SOUND_VOLUME or DOOR_SOUND_VOLUME
        PlayDoorAudioAt(door.Actor, door.OpenSoundKey, openVolume)
    elseif bWasOpen then
        QueueDoorCloseSound(door.Actor)
    end
end

local function CloseDoorIfOpen(door)
    SetDoorOpenState(door, false, true)
end

local function ShuffleDoors(doors)
    for index = #doors, 2, -1 do
        local swapIndex = math.random(index)
        doors[index], doors[swapIndex] = doors[swapIndex], doors[index]
    end
end

local function ClearToyProjectiles()
    if World == nil or World.FindActorsByTag == nil then
        return
    end

    local ok, found = pcall(function()
        return World.FindActorsByTag(TOY_PROJECTILE_TAG)
    end)
    if not ok or found == nil then
        return
    end

    for _, actor in ipairs(found) do
        if actor ~= nil then
            local okValid, valid = pcall(function()
                return actor.IsValid ~= nil and actor:IsValid()
            end)
            if okValid and valid then
                pcall(function()
                    actor:Destroy()
                end)
            end
        end
    end
end

local function RandomizeSingleDoorStatesOnWarp()
    local singleDoors = {}
    for _, door in ipairs(Doors) do
        if IsSingleDoor(door) then
            table.insert(singleDoors, door)
        end
    end

    local doorCount = #singleDoors
    if doorCount == 0 then
        return
    end

    ShuffleDoors(singleDoors)

    local maxOpenCount = math.min(MAX_OPEN_SINGLE_DOORS_ON_WARP, doorCount)
    local openCount = math.random(0, maxOpenCount)

    for index, door in ipairs(singleDoors) do
        SetDoorOpenState(door, index <= openCount, false)
    end
end

local function UpdateAutoCloseDoors(location)
    if not IsInAutoCloseDoorZone(location) then
        return
    end

    for name, _ in pairs(AUTO_CLOSE_DOOR_NAMES) do
        local door = FindDoorByName(name)
        if door ~= nil then
            CloseDoorIfOpen(door)
            door.bPermanentlyLocked = true
        end
    end
end

local function UnlockAutoCloseDoors()
    for name, _ in pairs(AUTO_CLOSE_DOOR_NAMES) do
        local door = FindDoorByName(name)
        if door ~= nil then
            door.bPermanentlyLocked = false
        end
    end
end

local function UpdateAutoCloseYDoors(location)
    if not IsInAutoCloseYDoorZone(location) then
        return
    end

    for name, _ in pairs(AUTO_CLOSE_Y_DOOR_NAMES) do
        CloseDoorIfOpen(FindDoorByName(name))
    end
end

local function ToggleDoor(door)
    if door == nil or door.Actor == nil or door.bPermanentlyLocked then
        return
    end

    local bWasOpen = door.IsOpen
    door.IsOpen = not door.IsOpen
    DoorStateByName[door.Name] = door.IsOpen

    local targetYaw = door.IsOpen and door.OpenYaw or door.CloseYaw
    door.StartYaw = door.CurrentYaw
    door.TargetYaw = targetYaw
    door.Elapsed = 0.0
    door.bPushPlayer = false

    SetDoorYaw(door, door.StartYaw)
    SyncDoorPhysics(door.Actor)

    if door.IsOpen then
        local openVolume = door.OpenSoundKey == DOOR_OPEN_SOUND_KEY and DOOR_OPEN_SOUND_VOLUME or DOOR_SOUND_VOLUME
        PlayDoorAudioAt(door.Actor, door.OpenSoundKey, openVolume)
    elseif bWasOpen then
        QueueDoorCloseSound(door.Actor)
    end

    print("[Door] toggle " .. tostring(door.Name)
        .. " open=" .. tostring(door.IsOpen)
        .. " startYaw=" .. tostring(door.StartYaw)
        .. " targetYaw=" .. tostring(targetYaw))
end

local function AddDoor(actor, openYaw)
    if actor == nil then
        return
    end

    local name = ActorName(actor)
    for _, door in ipairs(Doors) do
        if door.Actor == actor or door.Name == name then
            return
        end
    end

    local sceneYaw = GetActorYaw(actor)
    local isSceneOpen = math.abs(sceneYaw) > 45.0
    local bUseSceneYawAsOpen = isSceneOpen or math.abs(sceneYaw - openYaw) < 20.0
    local isOpen = INITIALLY_OPEN_NAMES[name] == true or bUseSceneYawAsOpen
    local closeYaw = isOpen and 0.0 or sceneYaw
    local resolvedOpenYaw = bUseSceneYawAsOpen and sceneYaw or openYaw
    local currentYaw = isOpen and resolvedOpenYaw or closeYaw
    local openSoundKey = DOUBLE_DOOR_NAMES[name] == true and HEAVY_DOOR_OPEN_SOUND_KEY or DOOR_OPEN_SOUND_KEY

    table.insert(Doors, {
        Actor = actor,
        Name = name,
        OpenYaw = resolvedOpenYaw,
        CloseYaw = closeYaw,
        OpenSoundKey = openSoundKey,
        IsOpen = isOpen,
        CurrentYaw = currentYaw,
        TargetYaw = currentYaw,
        StartYaw = currentYaw,
        Elapsed = DOOR_OPEN_DURATION,
        bPushPlayer = false,
        bPermanentlyLocked = false,
    })
    DoorStateByName[name] = isOpen
end

local function AddDoorsByTag(tag, openYaw)
    if World == nil then
        return
    end

    local ok, found = pcall(function()
        return World.FindActorsByTag(tag)
    end)
    if not ok or found == nil then
        return
    end

    for _, actor in ipairs(found) do
        AddDoor(actor, openYaw)
    end
end

local function AddDoorByName(name, openYaw)
    if World == nil then
        return
    end

    local ok, actor = pcall(function()
        return World.FindActorByName(name)
    end)
    if ok and actor ~= nil then
        AddDoor(actor, openYaw)
    end
end

local function InitDoors()
    if bDoorsInitialized then
        return
    end

    Doors = {}
    DoorStateByName = {}

    AddDoorsByTag("DoorOpenPlus", DOOR_OPEN_ANGLE_PLUS)
    AddDoorsByTag("DoorOpenMinus", DOOR_OPEN_ANGLE_MINUS)

    for name, _ in pairs(OPEN_PLUS_NAMES) do
        AddDoorByName(name, DOOR_OPEN_ANGLE_PLUS)
    end
    for name, _ in pairs(OPEN_MINUS_NAMES) do
        AddDoorByName(name, DOOR_OPEN_ANGLE_MINUS)
    end

    for _, door in ipairs(Doors) do
        SetDoorYaw(door, door.CurrentYaw)
        SyncDoorPhysics(door.Actor)
    end

    bDoorsInitialized = true
    print("[Door] initialized count=" .. tostring(#Doors))
end

local function DistanceSquared2D(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    return dx * dx + dy * dy
end

local function FindDoorByActor(actor)
    if actor == nil then
        return nil
    end

    for _, door in ipairs(Doors) do
        if door.Actor == actor then
            return door
        end
    end

    return nil
end

local function FindTargetedDoor()
    if World == nil or World.LineTraceObjects == nil or obj == nil then
        return nil
    end

    local camera = nil
    local okCamera = pcall(function()
        camera = obj:GetCamera()
    end)
    if not okCamera or camera == nil then
        return nil
    end

    local start = camera:GetLocation()
    local direction = camera.Forward
    if start == nil or direction == nil then
        return nil
    end

    local endPos = start + direction * INTERACT_DISTANCE
    local okHit, hit = pcall(function()
        return World.LineTraceObjects(start, endPos, obj)
    end)
    if not okHit or hit == nil or hit.Hit ~= true or hit.Actor == nil then
        return nil
    end

    local door = FindDoorByActor(hit.Actor)
    if door == nil then
        return nil
    end

    local distance = tonumber(hit.Distance)
    if distance ~= nil and distance > INTERACT_DISTANCE then
        return nil
    end

    return door
end

local function EnsureDoorPromptWidget()
    if DoorPromptWidget ~= nil then
        return DoorPromptWidget
    end

    if UI == nil or UI.CreateWidget == nil then
        return nil
    end

    local ok, widget = pcall(function()
        return UI.CreateWidget(DOOR_PROMPT_DOCUMENT_PATH)
    end)
    if not ok or widget == nil then
        return nil
    end

    DoorPromptWidget = widget
    pcall(function()
        DoorPromptWidget:SetWantsMouse(false)
    end)
    pcall(function()
        DoorPromptWidget:SetWantsKeyboard(false)
    end)
    pcall(function()
        DoorPromptWidget:SetBlocksGameInput(false)
    end)
    pcall(function()
        DoorPromptWidget:SetBlocksGameMouseLook(false)
    end)
    pcall(function()
        DoorPromptWidget:AddToViewportZ(80)
    end)

    return DoorPromptWidget
end

local function SetDoorPromptVisible(bVisible)
    local widget = EnsureDoorPromptWidget()
    if widget == nil or bDoorPromptVisible == bVisible then
        return
    end

    bDoorPromptVisible = bVisible
    pcall(function()
        widget:SetProperty(DOOR_PROMPT_ELEMENT_ID, "display", bVisible and "block" or "none")
    end)
end

local function UpdateDoorPrompt(door)
    if door == nil or door.bPermanentlyLocked then
        SetDoorPromptVisible(false)
        return
    end

    local widget = EnsureDoorPromptWidget()
    if widget == nil then
        return
    end

    local promptText = door.IsOpen and "[E] Close" or "[E] Open"
    pcall(function()
        widget:SetText(DOOR_PROMPT_ELEMENT_ID, promptText)
    end)
    SetDoorPromptVisible(true)
end

function BeginPlay()
    bCanWarp = true
    PendingDoorCloseSounds = {}
    bDoorsInitialized = false
    bInteractWasDown = false
    DoorPromptWidget = nil
    bDoorPromptVisible = false
end

function EndPlay()
    bCanWarp = true
    Doors = {}
    DoorStateByName = {}
    PendingDoorCloseSounds = {}
    bDoorsInitialized = false
    bInteractWasDown = false
    if DoorPromptWidget ~= nil then
        pcall(function()
            DoorPromptWidget:RemoveFromParent()
        end)
    end
    DoorPromptWidget = nil
    bDoorPromptVisible = false
end

function Tick(dt)
    if obj == nil then
        return
    end

    InitDoors()

    local location = obj:GetLocation()
    local bInZone = IsInTriggerZone(location)

    AddPlayerMovement()
    UpdateDoors(dt)
    UpdatePendingDoorCloseSounds(dt)
    UpdateAutoCloseDoors(location)
    UpdateAutoCloseYDoors(location)

    if bInZone and bCanWarp then
        obj:AddWorldOffset(Vec3(WARP_DELTA_X, WARP_DELTA_Y, WARP_DELTA_Z))
        GameManager:AdvanceAnomalyLoop()
        UnlockAutoCloseDoors()
        RandomizeSingleDoorStatesOnWarp()
        ClearToyProjectiles()
        bCanWarp = false
    elseif not bInZone then
        bCanWarp = true
    end

    local targetedDoor = FindTargetedDoor()
    UpdateDoorPrompt(targetedDoor)

    if Input ~= nil and Input.GetKey ~= nil then
        local ok, pressed = pcall(function()
            return Input.GetKey(INTERACT_KEY)
        end)
        if ok and pressed and not bInteractWasDown then
            if targetedDoor == nil then
                print("[Door] no targeted door in range. count=" .. tostring(#Doors))
            else
                ToggleDoor(targetedDoor)
                UpdateDoorPrompt(targetedDoor)
            end
        end
        bInteractWasDown = ok and pressed == true
    end
end

function OnOverlap(OtherActor)
end
