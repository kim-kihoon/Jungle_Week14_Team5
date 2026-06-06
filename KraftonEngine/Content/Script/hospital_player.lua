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
local DOOR_OPEN_DURATION = 0.45
local DOOR_YAW_SPEED = 90.0 / DOOR_OPEN_DURATION

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

    local yaw = 0.0
    local ok, rotation = pcall(function()
        return actor:GetRotation()
    end)
    if ok and rotation ~= nil and rotation.Z ~= nil then
        yaw = rotation.Z
    end
    local isOpen = INITIALLY_OPEN_NAMES[name] == true or math.abs(yaw - openYaw) < 20.0

    table.insert(Doors, {
        Actor = actor,
        Name = name,
        OpenYaw = openYaw,
        CloseYaw = 0.0,
        IsOpen = isOpen,
        CurrentYaw = isOpen and openYaw or 0.0,
        TargetYaw = isOpen and openYaw or 0.0,
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
    if not ok then
        return
    end
    if found == nil then
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
    if ok then
        AddDoor(actor, openYaw)
    end
end

local function InitDoors()
    Doors = {}
    DoorStateByName = {}

    AddDoorsByTag("DoorOpenPlus", 90.0)
    AddDoorsByTag("DoorOpenMinus", -90.0)

    for name, _ in pairs(OPEN_PLUS_NAMES) do
        AddDoorByName(name, 90.0)
    end
    for name, _ in pairs(OPEN_MINUS_NAMES) do
        AddDoorByName(name, -90.0)
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

local function RefreshDoorCollision(actor)
    if actor == nil then
        return
    end

    local ok, root = pcall(function()
        return actor:GetRootPrimitiveComponent()
    end)
    if ok and root ~= nil then
        pcall(function()
            root:SetCollisionEnabled(3)
        end)
    end
end

local function SetDoorYaw(door, yaw)
    if door == nil or door.Actor == nil then
        return false
    end

    local ok = pcall(function()
        door.Actor.Rotation = Vec3(0.0, 0.0, yaw)
    end)
    if ok then
        door.CurrentYaw = yaw
    end
    return ok
end

local function Approach(current, target, maxDelta)
    if current < target then
        return math.min(current + maxDelta, target)
    elseif current > target then
        return math.max(current - maxDelta, target)
    end
    return current
end

local function UpdateDoors(dt)
    local maxDelta = DOOR_YAW_SPEED * dt
    for _, door in ipairs(Doors) do
        if door.CurrentYaw ~= door.TargetYaw then
            local nextYaw = Approach(door.CurrentYaw, door.TargetYaw, maxDelta)
            if SetDoorYaw(door, nextYaw) then
                RefreshDoorCollision(door.Actor)
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
    door.TargetYaw = targetYaw
    print("[Door] toggle " .. tostring(door.Name) .. " open=" .. tostring(door.IsOpen) .. " targetYaw=" .. tostring(targetYaw))
end

function BeginPlay()
    bCanWarp = true
    bDoorsInitialized = false
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

    if not bDoorsInitialized then
        pcall(InitDoors)
    end

    if Input ~= nil and Input.GetKey ~= nil then
        local ok, pressed = pcall(function()
            return Input.GetKey(INTERACT_KEY)
        end)
        if ok and pressed and not bInteractWasDown then
            pcall(function()
                local door = FindNearestDoor(location)
                if door == nil then
                    print("[Door] no door in range. count=" .. tostring(#Doors))
                end
                ToggleDoor(door)
            end)
        end
        bInteractWasDown = ok and pressed == true
    end
end

function OnOverlap(OtherActor)
end
