local GameOverMonkey = {}

local COMPONENT_NAME = "GameOverMonkey"
local ANIMATION_PATH = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_Warning.uasset"
local ANIMATION_LOOPING = false
local ANIMATION_PLAY_RATE = 0.6

GameOverMonkey.PlayerActor = nil
GameOverMonkey.Mesh = nil

local function log_failure(message)
    print("[GameOverMonkey] " .. tostring(message))
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

function GameOverMonkey:PlayPresentationAnimation()
    local bVisible = self:SetVisible(true)
    local bAnimationStarted = self:PlayAnimation()
    return bVisible and bAnimationStarted
end

function GameOverMonkey:Hide()
    self:StopAnimation()
    return self:SetVisible(false)
end

function GameOverMonkey:ClearPresentation()
    return self:Hide()
end

function GameOverMonkey:Initialize(playerActor)
    self.PlayerActor = playerActor
    self.Mesh = nil
    self:ClearPresentation()
end

function GameOverMonkey:Shutdown()
    self:ClearPresentation()
    self.PlayerActor = nil
    self.Mesh = nil
end

return GameOverMonkey
