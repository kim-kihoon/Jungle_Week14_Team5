# Anomaly System

## 목적

- 게임 시작 또는 플레이어 워프 시 새로운 이상현상을 하나 활성화한다.
- 이상현상 대상은 `AnomalyCandidate` 태그가 붙은 액터 중에서 선택한다.
- 한 루프에는 액터 하나와 규칙 하나만 활성화한다.
- 플레이어가 현재 활성 이상현상 대상을 총으로 맞추면 이상현상을 클리어 상태로 표시하고 루프를 정지한다.
- 정지된 루프에서는 게임 시간이 흐르지 않고 `CymbalMonkey` 애니메이션도 멈춘다.
- `DoorEntry` 태그 문이 열리면 루프 시간을 초기화하고 시간 갱신을 재개한다.

## 전체 구조

```txt
GameManager
  ├─ 게임 시작과 워프 시 이상현상 세팅
  ├─ DoorEntry 문 열림 시 루프 시작 처리
  ├─ 총격 판정 보고 진입점 제공
  ├─ StopLoop / OnLoopStart로 루프 정지와 복구 처리
  └─ 게임 상태 리셋 시 이상현상 정리

AnomalyManager
  ├─ 후보 액터 수집
  ├─ 규칙 선택과 적용
  ├─ 활성 이상현상 상태 저장
  └─ Tick / Despawn / ReportShot 처리

Anomalies/*.lua
  ├─ PhotoInvisible
  ├─ NoShadow
  └─ OffscreenAnimation

DebugManager
  └─ 숫자 키 입력으로 특정 규칙 강제 적용
```

## 사용 방법

### 후보 액터 세팅

이상현상 후보가 될 액터에 아래 태그를 붙인다.

```txt
AnomalyCandidate
```

`AnomalyManager`는 `World.FindActorsByTag("AnomalyCandidate")`로 후보를 수집한다. 후보가 없으면 이상현상을 활성화하지 않고 실패 사유만 남긴다.

### 게임 시작과 워프 이벤트에서 호출

게임 시작 시 `GameManager:StartGame()`은 초기 이상현상 세팅을 수행한다. 이때 타이머는 바로 흐르지 않도록 루프 정지 상태로 시작한다.
새 스테이지가 세팅되면 플레이어 권총 탄환은 3발로 초기화된다.

플레이어 워프 직후에는 아래 함수를 호출해서 배치와 새 이상현상을 다시 세팅한다. 이 함수는 타이머를 재설정하지 않는다.

```lua
local GameManager = require("GameManager")

GameManager:OnWarp("PlayerWarp")
```

호출 결과는 성공 여부를 `boolean`으로 반환한다.

- `true`: 이상현상 하나가 활성화됨
- `false`: 게임이 Playing 상태가 아니거나 후보/규칙 적용에 실패함

### 루프 시작 문 이벤트에서 호출

`DoorEntry` 태그가 붙은 문이 닫힌 상태에서 열린 순간 아래 함수를 호출한다. 이 함수는 타이머를 `timeLimit`으로 되돌리고 루프 정지 상태를 해제한다.

```lua
GameManager:OnLoopStart("DoorEntryOpened")
```

이상현상 세팅은 `StartGame()`과 `OnWarp()`의 책임이며, `OnLoopStart()`는 타이머와 루프 재개만 담당한다.

### 총격 판정에서 호출

현재 플레이어 카메라 기준 라인트레이스 명중 액터를 아래 함수로 전달한다.

```lua
GameManager:ReportAnomalyShot(hit.Actor)
```

현재 활성 이상현상 대상과 같은 액터를 맞추면 `true`를 반환하고 `GameManager:StopLoop()`을 호출한다. 이때 활성 이상현상은 즉시 원복하지 않고, 게임 시간과 `CymbalMonkey` 애니메이션만 정지한다. 대상이 아니면 `false`를 반환하며 기존 투사체 스폰 흐름을 계속 진행하면 된다.
권총 발사 탄환은 총격 판정 전에 소모되므로 정답 이상현상, `Fake` 태그 대상, 일반 투사체 발사가 모두 스테이지당 3발 제한에 포함된다.

### 디버그 키

`GameManagerActor.lua`의 Tick에서 `DebugManager:Tick(dt, GameManager)`를 호출한다. 현재 매핑은 키보드 상단 숫자 키 기준으로 다음과 같다.

```txt
1 -> PhotoInvisible
2 -> NoShadow
3 -> OffscreenAnimation
4 -> OffscreenFacePlayer
5 -> BlackPhoto
6 -> NearSilentCymbalMonkey
```

디버그 키는 랜덤 규칙 선택을 거치지 않고 지정한 규칙만 강제로 적용한다. 단, 대상 액터는 `AnomalyCandidate` 후보 중에서 선택한다.
`OffscreenFacePlayer`는 디버그 전용 확인 규칙으로 유지하며, 일반 랜덤 규칙 풀에서는 제외한다.

### CymbalsMonkey 위치 마커

`CymbalMonkey.lua`는 아래 태그를 가진 마커 액터로 순간이동 위치를 결정한다.

```txt
CymbalsMonkeyInitPosition
CymbalsMonkeyPositionCandidate
```

- `CymbalsMonkeyInitPosition`: 게임 시작, 초기화, 루프 복구 시 원숭이가 돌아갈 위치/회전이다.
- `CymbalsMonkeyPositionCandidate`: 원숭이가 관측 후 시야에서 벗어났을 때 이동할 후보 위치/회전이다.
- 후보가 없거나 플레이어 위치에서 후보 위치까지 라인트레이스가 장애물에 막히지 않는 후보가 없으면 이동하지 않는다.

## 구현 흐름

### 게임 시작 세팅

```txt
GameManager:StartGame()
  ├─ Playing 상태 진입
  ├─ 플레이어 권총 탄환 3발 초기화
  ├─ 루프 정지 상태로 시작
  └─ GameManager:_SetupAnomaly("StartGame")
       ├─ 기존 활성 이상현상 Despawn
       ├─ 기존 배치 제거
       ├─ 새 배치 Spawn
       └─ AnomalyManager:SelectAndSpawn()
            ├─ AnomalyCandidate 후보 수집
            ├─ 후보 액터 1개 랜덤 선택
            ├─ 규칙 1개 랜덤 선택
            ├─ 규칙 Spawn(context) 호출
            └─ 성공 시 대상에 ActiveAnomalyTarget 태그 부여
```

### 워프 루프

```txt
GameManager:OnWarp("PlayerWarp")
  └─ GameManager:_SetupAnomaly("PlayerWarp")
       ├─ 플레이어 권총 탄환 3발 초기화
       ├─ 기존 활성 이상현상 Despawn
       ├─ 기존 배치 제거
       ├─ 새 배치 Spawn
       └─ AnomalyManager:SelectAndSpawn()
```

`OnWarp`는 타이머와 루프 정지 상태를 바꾸지 않는다.

### 루프 시작

```txt
GameManager:OnLoopStart("DoorEntryOpened")
  ├─ remainingTime을 timeLimit 초기값으로 복구
  ├─ 시간 갱신 재개
  └─ LoopRested 이벤트로 CymbalMonkey 애니메이션 재개
```

### 디버그 루프

```txt
DebugManager:Tick(dt, GameManager)
  └─ Input.GetKeyDown("1" / "2" / "3")
       └─ GameManager:DebugSpawnAnomalyRule(ruleName)
            └─ AnomalyManager:SelectAndSpawnRule(ruleName)
                 ├─ 기존 활성 이상현상 Despawn
                 ├─ 규칙 이름으로 규칙 검색
                 ├─ AnomalyCandidate 후보 수집
                 └─ 해당 규칙을 적용 가능한 후보에 Spawn
```

### 총격 클리어

```txt
GameManager:ReportAnomalyShot(actor)
  ├─ AnomalyManager:ReportShot(actor)
  │    ├─ 활성 대상과 같은 액터인지 확인
  │    └─ AnomalyManager:OnClear(active, "Shot")
  └─ 정답이면 GameManager:StopLoop()
       ├─ elapsedTime / remainingTime 갱신 정지
       └─ LoopStopped 이벤트로 CymbalMonkey 애니메이션 정지
```

### 호환 루프

```txt
GameManager:AdvanceAnomalyLoop()
  ├─ GameManager:OnWarp("AdvanceAnomalyLoop")
  └─ GameManager:OnLoopStart("AdvanceAnomalyLoop")
```

신규 플레이 흐름에서는 `AdvanceAnomalyLoop()`를 직접 호출하지 않고 `OnWarp()`와 `OnLoopStart()`를 각각 호출한다.

### CymbalsMonkey 순간이동

```txt
CymbalMonkey:Tick(dt)
  ├─ 프러스텀 + 라인트레이스로 원숭이 관측 여부 확인
  ├─ 한 번 관측되면 bObservedSinceTeleport = true
  └─ 관측된 뒤 프러스텀 밖으로 벗어나면 후보 위치 검색
       ├─ CymbalsMonkeyPositionCandidate 후보 수집
       ├─ 플레이어 위치에서 후보 위치까지 LineTraceObjects 검사
       ├─ 막히지 않은 후보 중 플레이어와 가장 가까운 후보 선택
       └─ 원숭이를 후보 위치/회전으로 이동 후 관측 상태 초기화
```

시야에 들어옴과 시야에서 나감은 모두 `World.IsActorInViewFrustum(obj)`와 `World.LineTraceObjects(...)`를 함께 사용한다. 프러스텀 안에 있으면 라인트레이스가 막혀도 이동하지 않는다. 프러스텀 안에 있어도 카메라에서 원숭이 위치까지 라인트레이스가 장애물에 막히면 관측되지 않은 상태로 본다. 라인트레이스가 아무 것도 맞추지 않으면 대상까지 막힘이 없는 것으로 처리한다.

### 리셋과 복구

`GameManager:Reset()`, `GameManager:GameOver()`, `GameManager:ClearGame()`은 모두 `AnomalyManager:Reset()`을 호출한다.

`AnomalyManager:Reset()`은 현재 활성 이상현상이 있으면 규칙의 `Despawn(context)`을 호출해서 태그, 그림자, 애니메이션 상태를 복구한다. `GameManager`는 이때 루프 정지 상태도 함께 정리한다.

새 이상현상을 로드하는 `GameManager:_SetupAnomaly()`, `AnomalyManager:SelectAndSpawn()`과 `AnomalyManager:SelectAndSpawnRule(ruleName)`도 시작 시 기존 활성 이상현상을 `Despawn`한다. 따라서 총격으로 클리어된 이상현상은 다음 워프나 디버그 규칙 전환 시 복구된 뒤 새 이상현상이 적용된다.

## Anomaly Rule 인터페이스

모든 규칙은 같은 인터페이스를 사용한다.

```lua
local Rule = {}

Rule.Name = "RuleName"

function Rule:Spawn(context)
    return true
end

function Rule:Tick(context)
end

function Rule:Despawn(context)
end

function Rule:IsCleared(context)
    return context.State.bCleared == true
end

return Rule
```

`Spawn(context)`가 `false, "reason"`을 반환하면 해당 규칙 적용은 실패한다. 디버그 강제 적용에서는 다른 후보 액터를 순회해서 같은 규칙을 다시 시도한다.

### Context 구성

```lua
{
    Manager = AnomalyManager,
    Target = targetActor,
    Rule = rule,
    Tags = AnomalyManager.Tags,
    State = {}
}
```

- `Target`: 이상현상이 적용될 액터
- `Tags`: 공통 태그 이름 모음
- `State`: 규칙이 원본 상태를 저장하는 임시 테이블
- `DeltaTime`: Tick 호출 시 추가됨
- `Reason`: Despawn 호출 시 추가됨

## 규칙 구현 원리

### PhotoInvisible

파일: `KraftonEngine/Content/Script/Anomalies/PhotoInvisible.lua`

목표는 월드에서는 보이지만 사진 캡처 결과에서는 보이지 않는 대상이다.

구현 방식:

- `Spawn`에서 대상 액터에 `PhotoInvisible` 태그를 추가한다.
- 대상이 원래 `PhotoInvisible` 태그를 가지고 있었는지 `context.State.HadPhotoInvisibleTag`에 저장한다.
- 사진 캡처 C++ 경로는 `PhotoInvisible` 태그가 붙은 액터를 사진 렌더에서 숨긴다.
- `Despawn`에서는 원래 태그가 없던 대상에 대해서만 `PhotoInvisible` 태그를 제거한다.

복구 원칙:

- 규칙이 추가한 태그만 제거한다.
- 에디터나 다른 시스템이 미리 붙인 태그는 보존한다.

### NoShadow

파일: `KraftonEngine/Content/Script/Anomalies/NoShadow.lua`

목표는 대상 본체는 보이지만 그림자만 사라지는 상태다.

구현 방식:

- 대상의 루트 `PrimitiveComponent`를 우선 찾는다.
- 루트 primitive가 없으면 대표 primitive를 사용한다.
- `Spawn`에서 `GetCastShadow()` 값을 저장한 뒤 `SetCastShadow(false)`를 호출한다.
- `Despawn`에서 저장해 둔 원래 그림자 상태로 복구한다.

적용 조건:

- 대상 액터에서 primitive 컴포넌트를 얻을 수 있어야 한다.
- `SetCastShadow`, `GetCastShadow` Lua 바인딩이 있어야 한다.

복구 원칙:

- 그림자를 무조건 켜지 않는다.
- 적용 전 값이 `false`였으면 해제 후에도 `false`로 유지한다.

### OffscreenAnimation

파일: `KraftonEngine/Content/Script/Anomalies/OffscreenAnimation.lua`

목표는 대상이 카메라 프러스텀 밖에 있을 때만 대상 skeleton에 호환되는 랜덤 애니메이션이 재생되는 상태다.

구현 방식:

- `Spawn`에서 대상의 `SkeletalMeshComponent`를 찾는다.
- 현재 애니메이션 경로, 재생 속도, 루프 여부, 재생 상태를 `context.State`에 저장한다.
- `SkeletalMeshComponent:GetCompatibleAnimationPaths()`로 대상의 현재 `SkeletalMesh` skeleton에 호환되는 애니메이션 경로 목록을 가져온다.
- 현재 재생 중인 애니메이션 경로는 후보에서 제외한다.
- 남은 후보 중 하나를 랜덤으로 골라 `context.State.OffscreenAnimationPath`에 저장한다.
- `Tick`마다 `World.IsActorInViewFrustum(context.Target)`으로 대상이 화면 안에 있는지 확인한다.
- 대상이 화면 밖으로 나가면 선택된 `OffscreenAnimationPath`로 `PlayAnimationByPath(path, true)`를 호출한다.
- 대상이 다시 화면 안으로 들어오면 `SetPlaying(false)`로 정지한다.
- `Despawn`에서 원래 애니메이션 경로, 재생 속도, 루프 여부, 재생 상태를 복구한다.

적용 조건:

- 대상 액터에 `SkeletalMeshComponent`가 있어야 한다.
- 현재 skeleton에 호환되고 현재 재생 중이지 않은 `UAnimSequence`가 하나 이상 있어야 한다.
- `PlayAnimationByPath` Lua 바인딩이 있어야 한다.
- `GetCompatibleAnimationPaths` Lua 바인딩이 있어야 한다.
- 프러스텀 판정은 `World.IsActorInViewFrustum(actor)` 바인딩을 사용한다.

복구 원칙:

- 기존 애니메이션 정보를 저장했다가 가능한 범위에서 되돌린다.
- 기존 재생 상태가 있으면 `SetPlaying(OriginalPlaying)`으로 복구한다.
- 기존 애니메이션 경로가 없으면 강제로 새 애니메이션을 지정하지 않는다.
- 기존 애니메이션 경로가 없으면 `StopAnimation()`으로 애니메이션을 비워 reference pose로 돌아가게 한다.
- 호환 가능한 다른 애니메이션이 없으면 하드코딩 애니메이션으로 대체하지 않고 `Spawn` 실패로 처리한다.

## C++ / Lua 연결 지점

### 사진 캡처

`ULuaAnimInstance::request_photo_capture`는 사진 촬영 시 `PhotoInvisible` 태그를 기준으로 대상을 숨긴다.

기존 `Fake` 태그는 이상현상 판정에 사용하지 않는다. 활성 이상현상 대상은 `ActiveAnomalyTarget` 태그를 사용한다.

### 컴포넌트 바인딩

`LuaScriptManager.cpp`에서 이상현상 규칙용 바인딩을 제공한다.

```txt
PrimitiveComponent:SetCastShadow(bool)
PrimitiveComponent:GetCastShadow()
PrimitiveComponent:SetVisibility(bool)
PrimitiveComponent:IsVisible()
Actor:GetAudioComponent()
AudioComponent:SetVolume(float)
AudioComponent:GetVolume()

SkeletalMeshComponent:GetAnimationPath()
SkeletalMeshComponent:GetCompatibleAnimationPaths()
SkeletalMeshComponent:GetPlayRate()
SkeletalMeshComponent:GetLooping()
SkeletalMeshComponent:IsPlaying()
World.IsActorInViewFrustum(actor)
World.GetGameTime()
World.GetRealTimeSeconds()
```

`AnomalyManager`의 랜덤 시드는 `os.time()`을 쓰지 않는다. 이 엔진 Lua는 `os` 라이브러리를 열지 않기 때문에, 엔진에서 안전하게 노출한 `World.GetRealTimeSeconds()`만 사용한다. 해당 바인딩이 없는 런타임에서는 고정 시드로 대체하지 않는다.

## 신규 규칙 추가 방법

1. `KraftonEngine/Content/Script/Anomalies/` 아래에 새 Lua 파일을 추가한다.
2. `Name`, `Spawn`, `Despawn`, 필요 시 `Tick`, `IsCleared`를 구현한다.
3. `AnomalyManager.lua`에서 `require("Anomalies/파일명")`으로 불러온다.
4. `AnomalyManager.Rules`에 규칙 테이블을 추가한다. 디버그 전용 규칙은 `AnomalyManager.AllRules`에는 등록하되 `AnomalyManager.Rules` 랜덤 풀에서는 제외한다.
5. 규칙이 변경한 액터/컴포넌트 상태는 반드시 `context.State`에 원본을 저장하고 `Despawn`에서 복구한다.

주의:

- 이 엔진의 커스텀 Lua require는 `Anomalies.PhotoInvisible` 같은 점 경로를 폴더 경로로 변환하지 않는다.
- 하위 폴더 모듈은 `require("Anomalies/PhotoInvisible")`처럼 `/`를 사용한다.
- `Spawn`에서 실패할 수 있는 규칙은 `false, "reason"`을 반환한다.
- 디버그 키로 강제 적용할 수 있게 하려면 규칙의 `Name`과 `DebugManager.Scenarios`의 `RuleName`을 일치시킨다.

## 현재 디버그 씬 체크리스트

- 후보 액터에 `AnomalyCandidate` 태그가 붙어 있는지 확인한다.
- `1`을 눌렀을 때 활성 대상에 `PhotoInvisible` 태그가 붙는지 확인한다.
- `2`를 눌렀을 때 대상 본체는 보이고 그림자만 사라지는지 확인한다.
- `3`을 눌렀을 때 대상이 화면 밖에 있을 때만 애니메이션이 재생되는지 확인한다.
- 다른 후보나 일반 오브젝트를 쏘면 클리어되지 않고, 활성 대상만 클리어되는지 확인한다.
- 활성 대상을 쏘면 게임 시간이 멈추고 `CymbalMonkey` 애니메이션도 정지하는지 확인한다.
- 한 스테이지에서 권총 발사는 정답 이상현상, `Fake` 태그 대상, 일반 투사체 발사를 합쳐 3회까지만 가능하다.
- 워프 후 새 스테이지가 세팅되면 권총 발사 가능 횟수가 다시 3회로 초기화된다.
- `DoorEntry` 문을 열면 `remainingTime`이 초기값으로 복구되고, 시간이 다시 흐르며 `CymbalMonkey` 애니메이션이 재개되는지 확인한다.
- 씬을 재시작하거나 게임이 리셋될 때 이전 이상현상 상태가 복구되는지 확인한다.

## OffscreenFacePlayer 추가 규칙

`OffscreenFacePlayer`는 플레이어가 대상을 한 번 관측한 뒤, 대상이 플레이어 카메라 프러스텀 밖에 있을 때만 대상 액터의 body yaw를 플레이어 방향으로 돌리는 규칙이다.

- 디버그 단축키: `4`
- 최초 관측 기준: 프러스텀 판정과 `World.LineTraceObjects`를 함께 사용한다.
- 발동 후 회전 기준: 라인트레이스는 사용하지 않고 프러스텀 판정만 사용한다.
- 스켈레탈 메시 대상: `World.IsComponentInViewFrustum(mesh)`로 실제 메시 컴포넌트 AABB를 검사한다.
- 일반 대상: 스켈레탈 메시가 없으면 `World.IsActorInViewFrustum(actor)`로 대체한다.
- 회전 방식: `Pitch=0`, `Roll=0`, `Yaw=플레이어 방향`으로 설정한다.
- 정지 조건: 대상이 프러스텀 안으로 들어오면 회전을 갱신하지 않는다.
- 복구 방식: 다음 루프, 리셋, 게임 종료 등으로 `Despawn`이 호출되면 `Spawn` 시점의 원래 회전으로 되돌린다.

디버그 키 매핑은 다음과 같다.

```txt
1 -> PhotoInvisible
2 -> NoShadow
3 -> OffscreenAnimation
4 -> OffscreenFacePlayer
5 -> BlackPhoto
6 -> NearSilentCymbalMonkey
```

`World.IsComponentInViewFrustum(component)`는 현재 월드의 활성 POV로 프러스텀을 만들고, 전달된 `UPrimitiveComponent`의 월드 AABB와 교차하는지 검사한다. 이 바인딩은 액터 루트 AABB와 실제 보이는 스켈레탈 메시 AABB가 달라지는 경우를 피하기 위해 사용한다.

### OffscreenFacePlayer 최초 관측 조건

`OffscreenFacePlayer`는 생성 직후 바로 회전하지 않는다. 플레이어가 대상을 한 번 관측해야 이상현상이 발동한다.

- 최초 관측 조건: 대상이 프러스텀 안에 있고, 플레이어 카메라에서 대상까지 `World.LineTraceObjects`가 막히지 않아야 한다.
- 최초 관측 전: 대상은 원래 회전을 유지한다.
- 최초 관측 후: 대상이 프러스텀 밖에 있을 때만 플레이어 방향으로 yaw를 갱신한다.
- 최초 관측 후 프러스텀 판정에는 라인트레이스를 사용하지 않는다.
- 라인트레이스 대상점은 대상 원점이 아니라 대상의 X/Y에 카메라 높이 Z를 맞춘 위치를 사용한다.

## BlackPhoto 추가 규칙

`BlackPhoto`는 활성 이상현상 대상이 촬영 순간 카메라에 관측될 때, 해당 사진 한 장의 내부 캡처 이미지를 전체 검은색으로 만드는 규칙이다.

- 디버그 단축키: `5`
- 태그: 활성 대상에 `PhotoBlackoutTarget` 태그를 붙이고, 원래 없던 태그만 `Despawn`에서 제거한다.
- 관측 조건: 대상이 프러스텀 안에 있고, 카메라에서 대상까지 `World.LineTraceObjects`가 막히지 않아야 한다.
- 프러스텀 기준: 스켈레탈 메시가 있으면 `World.IsComponentInViewFrustum(mesh)`를 사용하고, 없으면 `World.IsActorInViewFrustum(actor)`를 사용한다.
- 라인트레이스 대상점: 대상의 X/Y에 카메라 높이 Z를 맞춘 위치를 사용한다.
- 블랙아웃 범위: 폴라로이드 프레임은 유지하고, 사진 내부 캡처 텍스처만 검은색으로 clear한다.
- 적용 범위: 블랙아웃 여부는 촬영 입력 순간마다 다시 계산하며, 조건을 만족한 그 한 장에만 적용된다.

## NearSilentCymbalMonkey 추가 규칙

`NearSilentCymbalMonkey`는 플레이어가 활성 이상현상 대상 근처에 접근했을 때 `CymbalsMonkey` 태그를 가진 액터의 `AudioComponent` 볼륨을 0으로 낮추는 규칙이다.

- 디버그 키: `6`
- 원숭이 검색 기준: `World.FindActorsByTag("CymbalsMonkey")`
- 거리 기준: 플레이어 카메라 위치와 활성 이상현상 대상 위치 사이의 거리가 `2.5m` 이하일 때 발동한다.
- 음소거 방식: 별도 오디오 매니저 게이트를 만들지 않고, `CymbalsMonkey` 태그 액터의 대표 `AudioComponent:SetVolume(0)`을 호출한다.
- 복구 방식: 플레이어가 범위 밖으로 나가거나 다음 루프, 리셋, 게임 종료로 `Despawn`이 호출되면 저장해 둔 원래 볼륨으로 복구한다.
- 적용 대상: 정답 대상은 기존처럼 랜덤 `AnomalyCandidate`이며, 원숭이 자체를 정답 대상으로 바꾸지 않는다.
