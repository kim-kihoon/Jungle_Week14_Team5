local TitleMenu = {}

TitleMenu.DocumentPath = "Content/UI/TitleUI.rml"
TitleMenu.OptionDocumentPath = "Content/UI/TitleOptionUI.rml"
TitleMenu.CreditDocumentPath = "Content/UI/TitleCreditUI.rml"
TitleMenu.StartSceneName = "CymbalMonkey"
TitleMenu.Widget = nil
TitleMenu.PopupWidget = nil

local function call_if_exists(target, name, ...)
    if target ~= nil and type(target[name]) == "function" then
        target[name](target, ...)
    end
end

local function configure_menu_widget(widget)
    call_if_exists(widget, "SetWantsMouse", true)
    call_if_exists(widget, "SetWantsKeyboard", true)
    call_if_exists(widget, "SetBlocksGameInput", true)
    call_if_exists(widget, "SetBlocksGameMouseLook", true)
end

function TitleMenu:Show()
    if self.Widget == nil then
        self.Widget = UI.CreateWidget(self.DocumentPath)
    end

    if self.Widget == nil then
        print("[TitleMenu] Failed to create widget: " .. tostring(self.DocumentPath))
        return false
    end

    configure_menu_widget(self.Widget)
    self.Widget:AddToViewportZ(100)
    return true
end

function TitleMenu:Hide()
    self:HidePopup()
    if self.Widget ~= nil and self.Widget:IsInViewport() then
        self.Widget:RemoveFromParent()
    end
end

function TitleMenu:Dispose()
    self:Hide()
    self.Widget = nil
end

function TitleMenu:HidePopup()
    if self.PopupWidget ~= nil and self.PopupWidget:IsInViewport() then
        self.PopupWidget:RemoveFromParent()
    end
    self.PopupWidget = nil
end

function TitleMenu:ShowPopup(documentPath)
    self:HidePopup()

    self.PopupWidget = UI.CreateWidget(documentPath)
    if self.PopupWidget == nil then
        print("[TitleMenu] Failed to create popup widget: " .. tostring(documentPath))
        return false
    end

    configure_menu_widget(self.PopupWidget)
    self.PopupWidget:AddToViewportZ(110)
    return true
end

function TitleMenu:ShowOption()
    return self:ShowPopup(self.OptionDocumentPath)
end

function TitleMenu:ShowCredit()
    return self:ShowPopup(self.CreditDocumentPath)
end

return TitleMenu
