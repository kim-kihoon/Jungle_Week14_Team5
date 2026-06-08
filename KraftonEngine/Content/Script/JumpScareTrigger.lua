local TAG_ACTIVE = "JumpScareActive"
local TAG_TRIGGERED = "JumpScareTriggered"

-- 에디터 프로퍼티가 비어 있을 때만 사용하는 예비 애니메이션 경로다.
local ANIMATION_PATH = ""
local bShowMeshOnTrigger = true
local bPlayAnimationOnTrigger = true
local bMoveMeshOnTrigger = true
local bOneShot = true

local MOVE_OFFSET = Vec3(0.0, 0.0, 0.0)
local MOVE_DURATION = 0.5

local OriginalMeshLocation = nil
local MoveState = nil

local function is_valid_actor(actor)
    if actor == nil then
        return false
    end
    if actor.IsValid == nil then
        return true
    end

    local ok, valid = pcall(function()
        return actor:IsValid()
    end)
    return ok and valid == true
end

local function get_player_pawn()
    if World == nil or World.GetFirstPlayerController == nil then
        return nil
    end

    local controller = World.GetFirstPlayerController()
    if controller == nil or controller.GetPossessedPawn == nil then
        return nil
    end
    return controller:GetPossessedPawn()
end

local function is_player_actor(actor)
    local player = get_player_pawn()
    if player ~= nil and actor == player then
        return true
    end

    if actor ~= nil and actor.HasTag ~= nil then
        local ok, hasPlayerTag = pcall(function()
            return actor:HasTag("Player")
        end)
        return ok and hasPlayerTag == true
    end

    return false
end

local function get_target_actor()
    -- 기본은 이 스크립트가 붙은 액터 자신이다.
    return obj
end

local function get_target_mesh()
    local target = get_target_actor()
    if not is_valid_actor(target) or target.GetSkeletalMeshComponent == nil then
        return nil
    end

    local ok, mesh = pcall(function()
        return target:GetSkeletalMeshComponent()
    end)
    if not ok then
        return nil
    end
    return mesh
end

local function set_mesh_visible(mesh, visible)
    if mesh ~= nil and mesh.SetVisibility ~= nil then
        pcall(function()
            mesh:SetVisibility(visible)
        end)
    end
end

local function get_component_location(component)
    if component == nil or component.GetLocation == nil then
        return nil
    end

    local ok, location = pcall(function()
        return component:GetLocation()
    end)
    if not ok then
        return nil
    end
    return location
end

local function set_component_location(component, location)
    if component == nil or location == nil or component.SetLocation == nil then
        return false
    end

    local ok = pcall(function()
        component:SetLocation(location)
    end)
    return ok == true
end

local function read_script_property(name)
    if this == nil or this.GetProperty == nil then
        return nil
    end

    local ok, value = pcall(function()
        return this:GetProperty(name)
    end)
    if not ok then
        return nil
    end
    return value
end

local function play_mesh_animation(mesh)
    if not bPlayAnimationOnTrigger then
        return false
    end
    if mesh == nil or mesh.PlayAnimationByPath == nil then
        return false
    end

    local animationPath = ANIMATION_PATH
    local propertyPath = read_script_property("LoopAnimationPath")
    if type(propertyPath) == "string" and propertyPath ~= "" and propertyPath ~= "None" then
        animationPath = propertyPath
    end

    if type(animationPath) ~= "string" or animationPath == "" or animationPath == "None" then
        return false
    end

    local ok, result = pcall(function()
        return mesh:PlayAnimationByPath(animationPath, true)
    end)
    return ok and result ~= false
end

local function get_move_duration()
    local propertyDuration = tonumber(read_script_property("JumpScareMoveDuration"))
    if propertyDuration ~= nil and propertyDuration > 0 then
        return propertyDuration
    end
    return tonumber(MOVE_DURATION) or 0
end

local function get_target_location(startLocation)
    local bUseArrivalLocation = read_script_property("bUseJumpScareArrivalLocation") == true
    if bUseArrivalLocation then
        local arrivalLocation = read_script_property("JumpScareArrivalLocation")
        if arrivalLocation ~= nil then
            return arrivalLocation
        end
    end

    if startLocation == nil or MOVE_OFFSET == nil then
        return nil
    end
    return startLocation + MOVE_OFFSET
end

local function start_mesh_movement(mesh)
    if not bMoveMeshOnTrigger then
        MoveState = nil
        return false
    end

    local duration = get_move_duration()
    if duration <= 0 then
        MoveState = nil
        return false
    end

    local startLocation = OriginalMeshLocation or get_component_location(mesh)
    local targetLocation = get_target_location(startLocation)
    if startLocation == nil or targetLocation == nil then
        MoveState = nil
        return false
    end

    set_component_location(mesh, startLocation)
    MoveState = {
        Mesh = mesh,
        StartLocation = startLocation,
        TargetLocation = targetLocation,
        Elapsed = 0.0,
        Duration = duration
    }
    return true
end

local function run_jump_scare()
    local mesh = get_target_mesh()
    if OriginalMeshLocation ~= nil then
        set_component_location(mesh, OriginalMeshLocation)
    end
    if bShowMeshOnTrigger then
        set_mesh_visible(mesh, true)
    end
    play_mesh_animation(mesh)
    start_mesh_movement(mesh)
end

function BeginPlay()
    local mesh = get_target_mesh()
    if mesh ~= nil then
        OriginalMeshLocation = get_component_location(mesh)
        set_mesh_visible(mesh, false)
    end
end

function ResetJumpScare()
    MoveState = nil

    local mesh = get_target_mesh()
    if mesh == nil then
        return false
    end

    if mesh.StopAnimation ~= nil then
        pcall(function()
            mesh:StopAnimation()
        end)
    end
    if OriginalMeshLocation ~= nil then
        set_component_location(mesh, OriginalMeshLocation)
    end
    set_mesh_visible(mesh, false)
    return true
end

function OnOverlap(OtherActor, OverlappedComponent, OtherComp)
    if obj == nil or obj.HasTag == nil then
        return
    end

    if not obj:HasTag(TAG_ACTIVE) then
        return
    end

    if bOneShot and obj:HasTag(TAG_TRIGGERED) then
        return
    end

    if not is_player_actor(OtherActor) then
        return
    end

    if bOneShot and obj.AddTag ~= nil then
        obj:AddTag(TAG_TRIGGERED)
    end

    run_jump_scare()
end

function Tick(dt)
    if MoveState == nil then
        return
    end

    local mesh = MoveState.Mesh
    if mesh == nil then
        MoveState = nil
        return
    end

    MoveState.Elapsed = MoveState.Elapsed + (tonumber(dt) or 0)
    local alpha = MoveState.Elapsed / MoveState.Duration
    if alpha >= 1.0 then
        set_component_location(mesh, MoveState.TargetLocation)
        if mesh.StopAnimation ~= nil then
            pcall(function()
                mesh:StopAnimation()
            end)
        end
        set_mesh_visible(mesh, false)
        MoveState = nil
        return
    end
    if alpha < 0.0 then
        alpha = 0.0
    end

    local location = MoveState.StartLocation + (MoveState.TargetLocation - MoveState.StartLocation) * alpha
    set_component_location(mesh, location)
end
