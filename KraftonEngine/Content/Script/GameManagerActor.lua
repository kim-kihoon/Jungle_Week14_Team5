local GameManager = require("GameManager")
local DebugManager = require("DebugManager")

local function initialize_cymbal_monkey()
    if World == nil or World.FindActorByName == nil then
        print("[GameManagerActor] CymbalMonkey init failed: World.FindActorByName is unavailable")
        return false
    end

    local monkey = World.FindActorByName("Monkey")
    if monkey == nil then
        print("[GameManagerActor] CymbalMonkey init failed: Monkey actor not found")
        return false
    end

    if monkey.GetLuaScriptComponent == nil then
        print("[GameManagerActor] CymbalMonkey init failed: Monkey has no GetLuaScriptComponent binding")
        return false
    end

    local luaScript = monkey:GetLuaScriptComponent()
    if luaScript == nil then
        print("[GameManagerActor] CymbalMonkey init failed: Monkey LuaScriptComponent not found")
        return false
    end

    if luaScript.CallFunction == nil then
        print("[GameManagerActor] CymbalMonkey init failed: LuaScriptComponent.CallFunction is unavailable")
        return false
    end

    local ok = luaScript:CallFunction("InitializeFromGameManager")
    if not ok then
        print("[GameManagerActor] CymbalMonkey init failed: InitializeFromGameManager call failed")
        return false
    end

    print("[GameManagerActor] CymbalMonkey initialized")
    return true
end

function BeginPlay()
    GameManager:Reset()
    GameManager:SetTimeLimit(60)
    GameManager:StartGame()
    initialize_cymbal_monkey()
    print("[GameManagerActor] BeginPlay")
end

function EndPlay()
    GameManager:Reset()
    print("[GameManagerActor] EndPlay")
end

function Tick(dt)
    DebugManager:Tick(dt, GameManager)
    GameManager:Tick(dt)
end
