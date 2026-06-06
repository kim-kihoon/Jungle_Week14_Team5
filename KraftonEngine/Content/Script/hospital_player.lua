-- Hospital.Scene player warp: y > 27.132 and x < -3 -> offset by fixed delta (rotation unchanged).

local TRIGGER_Y_MIN = 27.132
local TRIGGER_X_MAX = -3.0
local WARP_DELTA_X = 8.368179
local WARP_DELTA_Y = -33.80393
local WARP_DELTA_Z = 0.0

local bCanWarp = true

local function IsInTriggerZone(location)
    return location.Y > TRIGGER_Y_MIN and location.X < TRIGGER_X_MAX
end

function BeginPlay()
    bCanWarp = true
end

function EndPlay()
    bCanWarp = true
end

function Tick(dt)
    if obj == nil then
        return
    end

    local location = obj:GetLocation()
    local bInZone = IsInTriggerZone(location)

    if bInZone and bCanWarp then
        obj:AddWorldOffset(Vec3(WARP_DELTA_X, WARP_DELTA_Y, WARP_DELTA_Z))
        bCanWarp = false
    elseif not bInZone then
        bCanWarp = true
    end
end

function OnOverlap(OtherActor)
end
