local TitleManager = {}

TitleManager.MainDocumentPath = "Content/UI/TitleUI.rml"
TitleManager.SettingDocumentPath = "Content/UI/SettingUI.rml"
TitleManager.CreditDocumentPath = "Content/UI/CreditUI.rml"
TitleManager.StartSceneName = "Hospital.Scene"
TitleManager.MainWidget = nil
TitleManager.PopupWidget = nil

local function add_widget_to_viewport(widget, z_order)
    if widget == nil then
        return false
    end

    if widget.SetWantsMouse ~= nil then
        widget:SetWantsMouse(true)
    end
    if widget.SetWantsKeyboard ~= nil then
        widget:SetWantsKeyboard(true)
    end
    if widget.SetBlocksGameInput ~= nil then
        widget:SetBlocksGameInput(true)
    end
    if widget.SetBlocksGameKeyboard ~= nil then
        widget:SetBlocksGameKeyboard(true)
    end
    if widget.SetBlocksGameMouseLook ~= nil then
        widget:SetBlocksGameMouseLook(true)
    end

    if widget.AddToViewportZ ~= nil then
        widget:AddToViewportZ(z_order)
    elseif widget.AddToViewport ~= nil then
        widget:AddToViewport()
    end

    return true
end

local function create_widget(document_path)
    if UI == nil or UI.CreateWidget == nil then
        return nil
    end

    return UI.CreateWidget(document_path)
end

function TitleManager:Show()
    if self.MainWidget ~= nil and self.MainWidget.IsInViewport ~= nil and self.MainWidget:IsInViewport() then
        return true
    end

    self.MainWidget = create_widget(self.MainDocumentPath)
    return add_widget_to_viewport(self.MainWidget, 100)
end

function TitleManager:ClosePopup()
    if self.PopupWidget ~= nil and self.PopupWidget.RemoveFromParent ~= nil then
        self.PopupWidget:RemoveFromParent()
    end
    self.PopupWidget = nil
end

function TitleManager:ShowPopup(document_path)
    self:ClosePopup()
    self.PopupWidget = create_widget(document_path)
    return add_widget_to_viewport(self.PopupWidget, 110)
end

function TitleManager:ShowSetting()
    return self:ShowPopup(self.SettingDocumentPath)
end

function TitleManager:ShowCredit()
    return self:ShowPopup(self.CreditDocumentPath)
end

function TitleManager:StartGame()
    self:Dispose()
    if Engine ~= nil and Engine.TransitionToScene ~= nil then
        Engine.TransitionToScene(self.StartSceneName)
    end
end

function TitleManager:ExitGame()
    if Engine ~= nil and Engine.Exit ~= nil then
        Engine.Exit()
    end
end

function TitleManager:Dispose()
    self:ClosePopup()
    if self.MainWidget ~= nil and self.MainWidget.RemoveFromParent ~= nil then
        self.MainWidget:RemoveFromParent()
    end
    self.MainWidget = nil
end

function BeginPlay()
    TitleManager:Show()
end

function EndPlay()
    TitleManager:Dispose()
end

function StartGame()
    TitleManager:StartGame()
end

function ShowSetting()
    TitleManager:ShowSetting()
end

function ShowCredit()
    TitleManager:ShowCredit()
end

function ClosePopup()
    TitleManager:ClosePopup()
end

function ExitGame()
    TitleManager:ExitGame()
end

return TitleManager
