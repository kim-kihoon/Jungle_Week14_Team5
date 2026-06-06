-- Hospital.Scene player warp: y > 27.132 and x < -3 -> offset by fixed delta (rotation unchanged).

local TRIGGER_Y_MIN = 27.132
local TRIGGER_X_MAX = -3.0
local WARP_DELTA_X = 8.368179
local WARP_DELTA_Y = -33.80393
local WARP_DELTA_Z = 0.0

local bCanWarp = true
local Doors = {}
local DoorStateByName = {}
local bDoorsInitialized = false
local bInteractWasDown = false

local INTERACT_KEY = 0x45 -- E
local KEY_W = 0x57
local KEY_A = 0x41
local KEY_S = 0x53
local KEY_D = 0x44
local INTERACT_DISTANCE = 3.5
local INTERACT_DISTANCE_SQ = INTERACT_DISTANCE * INTERACT_DISTANCE
local DOOR_OPEN_DURATION = 1.0
local DOOR_OPEN_ANGLE_PLUS = 70.0
local DOOR_OPEN_ANGLE_MINUS = -70.0
local DOOR_CONTACT_SLOP = 0.08
local DOOR_CONTACT_RAY_COUNT = 16
local DOOR_APPROACH_DOT_THRESHOLD = 1.0e-6

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

local function ToggleDoor(door)
    if door == nil or door.Actor == nil then
        return
    end

    door.IsOpen = not door.IsOpen
    DoorStateByName[door.Name] = door.IsOpen

    local targetYaw = door.IsOpen and door.OpenYaw or door.CloseYaw
    door.StartYaw = door.CurrentYaw
    door.TargetYaw = targetYaw
    door.Elapsed = 0.0
    door.bPushPlayer = false

    SetDoorYaw(door, door.StartYaw)
    SyncDoorPhysics(door.Actor)

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

    local closeYaw = GetActorYaw(actor)
    local isOpen = INITIALLY_OPEN_NAMES[name] == true or math.abs(closeYaw - openYaw) < 20.0
    local currentYaw = isOpen and openYaw or closeYaw

    table.insert(Doors, {
        Actor = actor,
        Name = name,
        OpenYaw = openYaw,
        CloseYaw = closeYaw,
        IsOpen = isOpen,
        CurrentYaw = currentYaw,
        TargetYaw = currentYaw,
        StartYaw = currentYaw,
        Elapsed = DOOR_OPEN_DURATION,
        bPushPlayer = false,
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

local function FindNearestDoor(location)
    local bestDoor = nil
    local bestDistanceSq = INTERACT_DISTANCE_SQ

    for _, door in ipairs(Doors) do
        if door.Actor ~= nil then
            local ok, doorLocation = pcall(function()
                return door.Actor:GetLocation()
            end)
            if ok and doorLocation ~= nil then
                local distSq = DistanceSquared2D(location, doorLocation)
                if distSq < bestDistanceSq then
                    bestDistanceSq = distSq
                    bestDoor = door
                end
            end
        end
    end

    return bestDoor
end

function BeginPlay()
    bCanWarp = true
    bDoorsInitialized = false
    bInteractWasDown = false
end

function EndPlay()
    bCanWarp = true
    Doors = {}
    DoorStateByName = {}
    bDoorsInitialized = false
    bInteractWasDown = false
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

    if bInZone and bCanWarp then
        obj:AddWorldOffset(Vec3(WARP_DELTA_X, WARP_DELTA_Y, WARP_DELTA_Z))
        bCanWarp = false
    elseif not bInZone then
        bCanWarp = true
    end

    if Input ~= nil and Input.GetKey ~= nil then
        local ok, pressed = pcall(function()
            return Input.GetKey(INTERACT_KEY)
        end)
        if ok and pressed and not bInteractWasDown then
            local door = FindNearestDoor(location)
            if door == nil then
                print("[Door] no door in range. count=" .. tostring(#Doors))
            else
                ToggleDoor(door)
            end
        end
        bInteractWasDown = ok and pressed == true
    end
end

function OnOverlap(OtherActor)
end
