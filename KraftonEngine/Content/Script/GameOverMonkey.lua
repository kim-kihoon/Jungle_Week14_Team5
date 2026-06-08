local GameOverMonkey = {}

local COMPONENT_NAME = "GameOverMonkey"
local ANIMATION_PATH = "Content/Data/CymbalMonkey/CymbalMonkey_Joints_Warning.uasset"
local ANIMATION_LOOPING = true
local PRESENTATION_SECONDS = 2.0

GameOverMonkey.PlayerActor = nil
GameOverMonkey.GameManager = nil
GameOverMonkey.UIManager = nil
GameOverMonkey.Mesh = nil
GameOverMonkey.StateChangedHandle = nil
GameOverMonkey.PresentationCoroutine = nil
GameOverMonkey.PresentationWaitRemaining = 0.0

function GameOverMonkey:GetMesh()
    if self.Mesh ~= nil then
        return self.Mesh
    end

    local actor = self.PlayerActor
    if actor == nil or actor.GetComponentByName == nil then
        return nil
    end

    local ok, component = pcall(function()
        return actor:GetComponentByName(COMPONENT_NAME)
    end)
    if ok then
        self.Mesh = component
    end

    return self.Mesh
end

function GameOverMonkey:SetVisible(visible)
    local mesh = self:GetMesh()
    if mesh == nil then
        return false
    end

    local bVisible = visible == true
    local bApplied = false
    if mesh.SetVisibility ~= nil then
        local ok = pcall(function()
            mesh:SetVisibility(bVisible)
        end)
        bApplied = bApplied or ok
    end
    if mesh.SetVisible ~= nil then
        local ok = pcall(function()
            mesh:SetVisible(bVisible)
        end)
        bApplied = bApplied or ok
    end

    return bApplied
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
    if mesh == nil or mesh.PlayAnimationByPath == nil then
        return false
    end

    local ok, result = pcall(function()
        return mesh:PlayAnimationByPath(ANIMATION_PATH, ANIMATION_LOOPING)
    end)
    return ok and result ~= false
end

function GameOverMonkey:Show()
    self:SetVisible(true)
    return self:PlayAnimation()
end

function GameOverMonkey:Hide()
    self:StopAnimation()
    return self:SetVisible(false)
end

function GameOverMonkey:StopPresentationCoroutine()
    self.PresentationCoroutine = nil
    self.PresentationWaitRemaining = 0.0
end

function GameOverMonkey:OpenGameOverScreen()
    if self.UIManager ~= nil and self.UIManager.ShowGameOver ~= nil then
        return self.UIManager:ShowGameOver()
    end

    return false
end

function GameOverMonkey:Tick(dt)
    if self.PresentationCoroutine == nil then
        return
    end

    if coroutine.status(self.PresentationCoroutine) == "dead" then
        self:StopPresentationCoroutine()
        return
    end

    self.PresentationWaitRemaining = self.PresentationWaitRemaining - (tonumber(dt) or 0.0)
    if self.PresentationWaitRemaining > 0.0 then
        return
    end

    local ok, waitSeconds = coroutine.resume(self.PresentationCoroutine)
    if not ok then
        self:StopPresentationCoroutine()
        return
    end

    if coroutine.status(self.PresentationCoroutine) == "dead" then
        self:StopPresentationCoroutine()
        return
    end

    self.PresentationWaitRemaining = math.max(0.0, tonumber(waitSeconds) or 0.0)
end

function GameOverMonkey:StartPresentation()
    self:StopPresentationCoroutine()
    self:Show()

    self.PresentationWaitRemaining = 0.0
    self.PresentationCoroutine = coroutine.create(function()
        coroutine.yield(PRESENTATION_SECONDS)
        self:OpenGameOverScreen()
    end)

    self:Tick(0.0)
end

function GameOverMonkey:ClearPresentation()
    self:StopPresentationCoroutine()
    self:Hide()
    if self.UIManager ~= nil and self.UIManager.DisposeGameOver ~= nil then
        self.UIManager:DisposeGameOver()
    end
end

function GameOverMonkey:ApplyState(nextState)
    if self.GameManager ~= nil
        and self.GameManager.State ~= nil
        and nextState == self.GameManager.State.GameOver then
        self:StartPresentation()
        return
    end

    self:ClearPresentation()
end

function GameOverMonkey:BindStateChanged()
    if self.StateChangedHandle ~= nil
        or self.GameManager == nil
        or self.GameManager.OnStateChanged == nil then
        return
    end

    self.StateChangedHandle = self.GameManager:OnStateChanged(function(nextState)
        self:ApplyState(nextState)
    end)
end

function GameOverMonkey:UnbindStateChanged()
    if self.StateChangedHandle == nil
        or self.GameManager == nil
        or self.GameManager.RemoveListener == nil then
        self.StateChangedHandle = nil
        return
    end

    self.GameManager:RemoveListener("StateChanged", self.StateChangedHandle)
    self.StateChangedHandle = nil
end

function GameOverMonkey:Initialize(playerActor, gameManager, uiManager)
    self:UnbindStateChanged()
    self.PlayerActor = playerActor
    self.GameManager = gameManager
    self.UIManager = uiManager
    self.Mesh = nil
    self:BindStateChanged()
    self:ClearPresentation()
end

function GameOverMonkey:Shutdown()
    self:UnbindStateChanged()
    self:ClearPresentation()
    self.PlayerActor = nil
    self.GameManager = nil
    self.UIManager = nil
    self.Mesh = nil
end

return GameOverMonkey
