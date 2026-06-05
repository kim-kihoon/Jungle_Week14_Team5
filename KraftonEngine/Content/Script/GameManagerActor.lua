local GameManager = require("GameManager")

function BeginPlay()
    GameManager:Reset()

    GameManager:SetTimeLimit(60)



    GameManager:StartGame()
    print("[GameManagerActor] BeginPlay")
end

function EndPlay()
    GameManager:Reset()
    print("[GameManagerActor] EndPlay")
end

function Tick(dt)
    GameManager:Tick(dt)
end
