local ToolManager = require("ToolManager")

local UIManager = {}

UIManager.DoorPromptDocumentPath = "Content/UI/HospitalDoorPrompt.rml"
UIManager.DoorPromptElementId = "door_prompt"
UIManager.ControlPromptDocumentPath = "Content/UI/HospitalControlPrompt.rml"
UIManager.ControlPromptElementId = "control_prompt"
UIManager.TimerPromptDocumentPath = "Content/UI/HospitalTimer.rml"
UIManager.TimerPromptElementId = "timer_display"
UIManager.TitleDocumentPath = "Content/UI/TitleUI.rml"
UIManager.TitleSettingDocumentPath = "Content/UI/SettingUI.rml"
UIManager.TitleCreditDocumentPath = "Content/UI/CreditUI.rml"
UIManager.GameOverDocumentPath = "Content/UI/GameOverUI.rml"
UIManager.TimerColorNormal = "rgb(71, 255, 105)"
UIManager.TimerColorWarning = "rgb(255, 71, 71)"
UIManager.TimerWarningSeconds = 30

UIManager.DoorPromptWidget = nil
UIManager.bDoorPromptVisible = false
UIManager.ControlPromptWidget = nil
UIManager.bControlPromptVisible = false
UIManager.LastControlPromptText = nil
UIManager.TimerPromptWidget = nil
UIManager.bTimerPromptVisible = false
UIManager.LastTimerDisplaySeconds = nil
UIManager.LastTimerColor = nil
UIManager.bTimerUIEverStarted = false
UIManager.bTimerUIWasRunning = false
UIManager.TimerUIFrozenSeconds = nil
UIManager.TimerUILastLiveSeconds = 0
UIManager.TitleWidget = nil
UIManager.TitlePopupWidget = nil
UIManager.GameOverWidget = nil

local unpack_args = table.unpack or unpack

local function call_if_exists(object, functionName, ...)
    if object == nil or object[functionName] == nil then
        return false
    end

    local args = { ... }
    local ok = pcall(function()
        object[functionName](object, unpack_args(args))
    end)
    return ok == true
end

function UIManager:CreateWidget(documentPath)
    if UI == nil or UI.CreateWidget == nil then
        return nil
    end

    local ok, widget = pcall(function()
        return UI.CreateWidget(documentPath)
    end)
    if ok then
        return widget
    end
    return nil
end

function UIManager:AddWidgetToViewport(widget, zOrder, options)
    if widget == nil then
        return false
    end

    options = options or {}
    call_if_exists(widget, "SetWantsMouse", options.WantsMouse == true)
    call_if_exists(widget, "SetWantsKeyboard", options.WantsKeyboard == true)
    call_if_exists(widget, "SetBlocksGameInput", options.BlocksGameInput == true)
    call_if_exists(widget, "SetBlocksGameKeyboard", options.BlocksGameKeyboard == true)
    call_if_exists(widget, "SetBlocksGameMouseLook", options.BlocksGameMouseLook == true)

    if widget.AddToViewportZ ~= nil then
        local ok = pcall(function()
            widget:AddToViewportZ(zOrder or 0)
        end)
        if ok then
            return true
        end
    end

    return call_if_exists(widget, "AddToViewport")
end

function UIManager:RemoveWidget(widget)
    if widget ~= nil then
        call_if_exists(widget, "RemoveFromParent")
    end
end

local function set_widget_display(widget, elementId, bVisible)
    if widget == nil or widget.SetProperty == nil then
        return
    end

    pcall(function()
        widget:SetProperty(elementId, "display", bVisible and "block" or "none")
    end)
end

local function set_widget_text(widget, elementId, text)
    if widget == nil or widget.SetText == nil then
        return
    end

    pcall(function()
        widget:SetText(elementId, text)
    end)
end

local function set_widget_property(widget, elementId, propertyName, value)
    if widget == nil or widget.SetProperty == nil then
        return
    end

    pcall(function()
        widget:SetProperty(elementId, propertyName, value)
    end)
end

function UIManager:GetActionMappingDisplayName(name, fallback)
    if Input == nil or Input.GetActionMappingDisplayName == nil then
        return fallback
    end

    local ok, displayName = pcall(function()
        return Input.GetActionMappingDisplayName(name)
    end)
    if ok and displayName ~= nil and displayName ~= "" then
        return tostring(displayName)
    end
    return fallback
end

function UIManager:FormatActionPrompt(name, fallback)
    return "[" .. self:GetActionMappingDisplayName(name, fallback) .. "]"
end

function UIManager:ResetHospital()
    self:RemoveWidget(self.DoorPromptWidget)
    self:RemoveWidget(self.ControlPromptWidget)
    self:RemoveWidget(self.TimerPromptWidget)
    self:DisposeTitle()
    self:DisposeGameOver()

    self.DoorPromptWidget = nil
    self.bDoorPromptVisible = false
    self.ControlPromptWidget = nil
    self.bControlPromptVisible = false
    self.LastControlPromptText = nil
    self.TimerPromptWidget = nil
    self.bTimerPromptVisible = false
    self.LastTimerDisplaySeconds = nil
    self.LastTimerColor = nil
    self.bTimerUIEverStarted = false
    self.bTimerUIWasRunning = false
    self.TimerUIFrozenSeconds = nil
    self.TimerUILastLiveSeconds = 0
    self.GameOverWidget = nil
end

function UIManager:EnsureDoorPromptWidget()
    if self.DoorPromptWidget ~= nil then
        return self.DoorPromptWidget
    end

    self.DoorPromptWidget = self:CreateWidget(self.DoorPromptDocumentPath)
    self:AddWidgetToViewport(self.DoorPromptWidget, 80, {})
    return self.DoorPromptWidget
end

function UIManager:SetDoorPromptVisible(bVisible)
    local widget = self:EnsureDoorPromptWidget()
    if widget == nil or self.bDoorPromptVisible == bVisible then
        return
    end

    self.bDoorPromptVisible = bVisible
    set_widget_display(widget, self.DoorPromptElementId, bVisible)
end

function UIManager:UpdateDoorPrompt(door)
    if door == nil or door.bPermanentlyLocked then
        self:SetDoorPromptVisible(false)
        return
    end

    local widget = self:EnsureDoorPromptWidget()
    if widget == nil then
        return
    end

    local interactPrompt = self:FormatActionPrompt("Interact", "E")
    local promptText = door.IsOpen and (interactPrompt .. " Close") or (interactPrompt .. " Open")
    set_widget_text(widget, self.DoorPromptElementId, promptText)
    self:SetDoorPromptVisible(true)
end

function UIManager:EnsureControlPromptWidget()
    if self.ControlPromptWidget ~= nil then
        return self.ControlPromptWidget
    end

    self.ControlPromptWidget = self:CreateWidget(self.ControlPromptDocumentPath)
    self:AddWidgetToViewport(self.ControlPromptWidget, 75, {})
    return self.ControlPromptWidget
end

function UIManager:SetControlPromptVisible(bVisible)
    local widget = self:EnsureControlPromptWidget()
    if widget == nil or self.bControlPromptVisible == bVisible then
        return
    end

    self.bControlPromptVisible = bVisible
    set_widget_display(widget, self.ControlPromptElementId, bVisible)
end

function UIManager:UpdateControlPrompt()
    local widget = self:EnsureControlPromptWidget()
    if widget == nil then
        return
    end

    local firePrompt = self:FormatActionPrompt("Fire", "LMB")
    local toolPrompt = self:FormatActionPrompt("Jump", "Space")
    local promptText = ToolManager:IsCamera()
        and (firePrompt .. " Shoot\n" .. toolPrompt .. " Pistol")
        or (firePrompt .. " Shoot\n" .. toolPrompt .. " Camera")

    if self.LastControlPromptText ~= promptText then
        self.LastControlPromptText = promptText
        set_widget_text(widget, self.ControlPromptElementId, promptText)
    end
    self:SetControlPromptVisible(true)
end

local function format_countdown_seconds(totalSeconds)
    totalSeconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%d:%02d", minutes, seconds)
end

function UIManager:GetTimerDisplaySeconds(gameManager)
    if gameManager == nil or gameManager.GetRemainingTime == nil then
        return 0
    end

    local remainingTime = tonumber(gameManager:GetRemainingTime()) or 0
    return math.max(0, math.ceil(remainingTime - 0.001))
end

function UIManager:IsTimerRunning(gameManager)
    return gameManager ~= nil
        and gameManager.IsPlaying ~= nil
        and gameManager:IsPlaying()
        and gameManager.IsCymbalMonkeyCycleStarted ~= nil
        and gameManager:IsCymbalMonkeyCycleStarted()
        and gameManager.IsLoopStopped ~= nil
        and not gameManager:IsLoopStopped()
end

function UIManager:EnsureTimerPromptWidget()
    if self.TimerPromptWidget ~= nil then
        return self.TimerPromptWidget
    end

    self.TimerPromptWidget = self:CreateWidget(self.TimerPromptDocumentPath)
    self:AddWidgetToViewport(self.TimerPromptWidget, 85, {})
    set_widget_text(self.TimerPromptWidget, self.TimerPromptElementId, "0:00")
    set_widget_property(self.TimerPromptWidget, self.TimerPromptElementId, "color", self.TimerColorNormal)
    return self.TimerPromptWidget
end

function UIManager:SetTimerPromptVisible(bVisible)
    local widget = self:EnsureTimerPromptWidget()
    if widget == nil or self.bTimerPromptVisible == bVisible then
        return
    end

    self.bTimerPromptVisible = bVisible
    set_widget_display(widget, self.TimerPromptElementId, bVisible)
end

function UIManager:UpdateTimerPrompt(gameManager)
    local widget = self:EnsureTimerPromptWidget()
    if widget == nil then
        return
    end

    local bTimerRunning = self:IsTimerRunning(gameManager)
    local displaySeconds = 0
    local bApplyWarningColor = false

    if bTimerRunning then
        self.bTimerUIEverStarted = true
        self.bTimerUIWasRunning = true
        displaySeconds = self:GetTimerDisplaySeconds(gameManager)
        self.TimerUILastLiveSeconds = displaySeconds
        bApplyWarningColor = true
    else
        if self.bTimerUIWasRunning then
            self.TimerUIFrozenSeconds = self.TimerUILastLiveSeconds
            self.bTimerUIWasRunning = false
        end

        if self.bTimerUIEverStarted then
            displaySeconds = self.TimerUIFrozenSeconds or 0
            bApplyWarningColor = true
        end
    end

    local displayText = format_countdown_seconds(displaySeconds)
    local displayColor = self.TimerColorNormal
    if bApplyWarningColor and displaySeconds <= self.TimerWarningSeconds then
        displayColor = self.TimerColorWarning
    end

    if self.LastTimerDisplaySeconds ~= displaySeconds then
        self.LastTimerDisplaySeconds = displaySeconds
        set_widget_text(widget, self.TimerPromptElementId, displayText)
    end

    if self.LastTimerColor ~= displayColor then
        self.LastTimerColor = displayColor
        set_widget_property(widget, self.TimerPromptElementId, "color", displayColor)
    end

    self:SetTimerPromptVisible(true)
end

function UIManager:ShowTitle()
    if self.TitleWidget ~= nil and self.TitleWidget.IsInViewport ~= nil then
        local ok, bInViewport = pcall(function()
            return self.TitleWidget:IsInViewport()
        end)
        if ok and bInViewport then
            return true
        end
    end

    self.TitleWidget = self:CreateWidget(self.TitleDocumentPath)
    return self:AddWidgetToViewport(self.TitleWidget, 100, {
        WantsMouse = true,
        WantsKeyboard = true,
        BlocksGameInput = true,
        BlocksGameKeyboard = true,
        BlocksGameMouseLook = true
    })
end

function UIManager:CloseTitlePopup()
    self:RemoveWidget(self.TitlePopupWidget)
    self.TitlePopupWidget = nil
end

function UIManager:ShowTitlePopup(documentPath)
    self:CloseTitlePopup()
    self.TitlePopupWidget = self:CreateWidget(documentPath)
    return self:AddWidgetToViewport(self.TitlePopupWidget, 110, {
        WantsMouse = true,
        WantsKeyboard = true,
        BlocksGameInput = true,
        BlocksGameKeyboard = true,
        BlocksGameMouseLook = true
    })
end

function UIManager:ShowTitleSetting()
    return self:ShowTitlePopup(self.TitleSettingDocumentPath)
end

function UIManager:ShowTitleCredit()
    return self:ShowTitlePopup(self.TitleCreditDocumentPath)
end

function UIManager:DisposeTitle()
    self:CloseTitlePopup()
    self:RemoveWidget(self.TitleWidget)
    self.TitleWidget = nil
end

function UIManager:ShowGameOver()
    if self.GameOverWidget ~= nil and self.GameOverWidget.IsInViewport ~= nil then
        local ok, bInViewport = pcall(function()
            return self.GameOverWidget:IsInViewport()
        end)
        if ok and bInViewport then
            return true
        end
    end

    self:RemoveWidget(self.DoorPromptWidget)
    self:RemoveWidget(self.ControlPromptWidget)
    self:RemoveWidget(self.TimerPromptWidget)
    self.DoorPromptWidget = nil
    self.ControlPromptWidget = nil
    self.TimerPromptWidget = nil
    self.bDoorPromptVisible = false
    self.bControlPromptVisible = false
    self.bTimerPromptVisible = false

    self.GameOverWidget = self:CreateWidget(self.GameOverDocumentPath)
    return self:AddWidgetToViewport(self.GameOverWidget, 120, {
        WantsMouse = true,
        WantsKeyboard = true,
        BlocksGameInput = true,
        BlocksGameKeyboard = true,
        BlocksGameMouseLook = true
    })
end

function UIManager:DisposeGameOver()
    self:RemoveWidget(self.GameOverWidget)
    self.GameOverWidget = nil
end

return UIManager
