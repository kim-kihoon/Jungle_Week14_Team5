local TitleMenu = require("TitleMenu")

local InputWarmupSeconds = 0.25
local ElapsedSinceBeginPlay = 0
local bAcceptMenuInput = false

local function can_accept_menu_input(actionName)
    if bAcceptMenuInput then
        return true
    end

    print("[TitleGameManagerActor] Ignored early menu action: " .. tostring(actionName))
    return false
end

function BeginPlay()
    ElapsedSinceBeginPlay = 0
    bAcceptMenuInput = false
    TitleMenu:Show()
    print("[TitleGameManagerActor] BeginPlay")
end

function StartGame()
    if not can_accept_menu_input("StartGame") then
        return
    end

    TitleMenu:Hide()
    Engine.TransitionToScene(TitleMenu.StartSceneName)
    print("[TitleGameManagerActor] StartGame -> " .. tostring(TitleMenu.StartSceneName))
end

function ShowOption()
    if not can_accept_menu_input("ShowOption") then
        return
    end

    TitleMenu:ShowOption()
end

function ShowCredit()
    if not can_accept_menu_input("ShowCredit") then
        return
    end

    TitleMenu:ShowCredit()
end

function HidePopup()
    TitleMenu:HidePopup()
end

function ExitGame()
    if not can_accept_menu_input("ExitGame") then
        return
    end

    TitleMenu:Hide()
    Engine.Exit()
end

function EndPlay()
    TitleMenu:Dispose()
    print("[TitleGameManagerActor] EndPlay")
end

function Tick(dt)
    if not bAcceptMenuInput then
        ElapsedSinceBeginPlay = ElapsedSinceBeginPlay + (tonumber(dt) or 0)
        if ElapsedSinceBeginPlay >= InputWarmupSeconds then
            bAcceptMenuInput = true
        end
    end
end
