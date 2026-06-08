local SettingManager = {}

SettingManager.GammaOptions = {
    { Label = "Darker", Value = 2.0 },
    { Label = "Default", Value = 2.4 },
    { Label = "Brighter", Value = 2.8 },
}

SettingManager.MasterVolumeOptions = {
    { Label = "0", Value = 0.0 },
    { Label = "50", Value = 0.5 },
    { Label = "100", Value = 1.0 },
}

SettingManager.MouseSensitivityOptions = {
    { Label = "Low", Value = 0.1 },
    { Label = "Normal", Value = 0.2 },
    { Label = "High", Value = 0.35 },
}

SettingManager.GammaIndex = 2
SettingManager.MasterVolumeIndex = 3
SettingManager.MouseSensitivityIndex = 2
SettingManager.bInvertY = false
SettingManager.bHeadBob = true
SettingManager.bControlPrompt = true

local function cycle_index(currentIndex, count)
    currentIndex = tonumber(currentIndex) or 1
    count = tonumber(count) or 1
    if count <= 0 then
        return 1
    end
    return (currentIndex % count) + 1
end

local function set_widget_text(widget, elementId, text)
    if widget == nil or widget.SetText == nil then
        return
    end

    pcall(function()
        widget:SetText(elementId, text)
    end)
end

local function format_toggle(bEnabled)
    return bEnabled and "On" or "Off"
end

function SettingManager:GetGammaOption()
    return self.GammaOptions[self.GammaIndex] or self.GammaOptions[2]
end

function SettingManager:GetMasterVolumeOption()
    return self.MasterVolumeOptions[self.MasterVolumeIndex] or self.MasterVolumeOptions[3]
end

function SettingManager:GetMouseSensitivityOption()
    return self.MouseSensitivityOptions[self.MouseSensitivityIndex] or self.MouseSensitivityOptions[2]
end

function SettingManager:IsHeadBobEnabled()
    return self.bHeadBob == true
end

function SettingManager:IsControlPromptEnabled()
    return self.bControlPrompt == true
end

function SettingManager:Apply()
    local gamma = self:GetGammaOption().Value
    if Engine ~= nil then
        if Engine.SetGammaCorrectionEnabled ~= nil then
            pcall(function()
                Engine.SetGammaCorrectionEnabled(true)
            end)
        end
        if Engine.SetGamma ~= nil then
            pcall(function()
                Engine.SetGamma(gamma)
            end)
        end
    end

    if Audio ~= nil and Audio.SetMasterVolume ~= nil then
        local volume = self:GetMasterVolumeOption().Value
        pcall(function()
            Audio.SetMasterVolume(volume)
        end)
    end
end

function SettingManager:ApplyPlayerSettings(player)
    if player == nil then
        return
    end

    local sensitivity = self:GetMouseSensitivityOption().Value
    if player.SetMouseSensitivity ~= nil then
        pcall(function()
            player:SetMouseSensitivity(sensitivity)
        end)
    end

    if player.SetInvertMouseY ~= nil then
        pcall(function()
            player:SetInvertMouseY(self.bInvertY == true)
        end)
    end
end

function SettingManager:ApplyAll(player)
    self:Apply()
    self:ApplyPlayerSettings(player)
end

function SettingManager:RefreshWidget(widget)
    set_widget_text(widget, "setting_gamma_button", "Gamma: " .. self:GetGammaOption().Label)
    set_widget_text(widget, "setting_volume_button", "Master Volume: " .. self:GetMasterVolumeOption().Label)
    set_widget_text(widget, "setting_mouse_button", "Mouse Sensitivity: " .. self:GetMouseSensitivityOption().Label)
    set_widget_text(widget, "setting_invert_button", "Invert Y: " .. format_toggle(self.bInvertY))
    set_widget_text(widget, "setting_headbob_button", "Head Bob: " .. format_toggle(self.bHeadBob))
    set_widget_text(widget, "setting_control_prompt_button", "Control Prompt: " .. format_toggle(self.bControlPrompt))
end

function SettingManager:CycleGamma()
    self.GammaIndex = cycle_index(self.GammaIndex, #self.GammaOptions)
    self:Apply()
end

function SettingManager:CycleMasterVolume()
    self.MasterVolumeIndex = cycle_index(self.MasterVolumeIndex, #self.MasterVolumeOptions)
    self:Apply()
end

function SettingManager:CycleMouseSensitivity(player)
    self.MouseSensitivityIndex = cycle_index(self.MouseSensitivityIndex, #self.MouseSensitivityOptions)
    self:ApplyPlayerSettings(player)
end

function SettingManager:ToggleInvertY(player)
    self.bInvertY = not self.bInvertY
    self:ApplyPlayerSettings(player)
end

function SettingManager:ToggleHeadBob()
    self.bHeadBob = not self.bHeadBob
end

function SettingManager:ToggleControlPrompt()
    self.bControlPrompt = not self.bControlPrompt
end

return SettingManager
