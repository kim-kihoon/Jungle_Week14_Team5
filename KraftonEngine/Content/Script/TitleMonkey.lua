local START_ANIMATION_PATH = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_Warning.uasset"
local START_ANIMATION_PLAY_RATE = 0.6

local Mesh = nil

local function cache_mesh()
    if Mesh ~= nil then
        return Mesh
    end

    if obj ~= nil and obj.GetSkeletalMeshComponent ~= nil then
        Mesh = obj:GetSkeletalMeshComponent()
    end

    return Mesh
end

function PlayStartAnimation()
    local mesh = cache_mesh()
    if mesh == nil or mesh.PlayAnimationByPath == nil then
        return false
    end

    local ok, result = pcall(function()
        return mesh:PlayAnimationByPath(START_ANIMATION_PATH, false)
    end)

    if not ok or result == false then
        return false
    end

    if mesh.SetPlayRate ~= nil then
        pcall(function()
            mesh:SetPlayRate(START_ANIMATION_PLAY_RATE)
        end)
    end

    return true
end

function BeginPlay()
    cache_mesh()
end

function EndPlay()
    Mesh = nil
end
