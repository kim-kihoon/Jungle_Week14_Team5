# Anomaly System

## 목표

- 이상현상 추가 비용 최소화
- Lua 파일만 추가해서 신규 이상현상 구현 가능
- 환경 변화 / 적 생성 / 함정 등을 동일한 구조로 관리
- GameManager는 이상현상 세부 구현을 몰라도 동작 가능

---

# 구조

```txt
GameManager
    ↓
AnomalyManager
    ↓
Anomaly (Lua Module)
    ↓
SpawnPoint
```

---

# GameManager

역할

- 게임 시작
- 제한시간 관리
- 스테이지 진행
- 승리/패배 판정

예시

```txt
GameManager
 ├─ CurrentStage
 ├─ RemainingTime
 ├─ StartStage()
 ├─ CompleteStage()
 └─ FailStage()
```

---

# AnomalyManager

역할

- 이상현상 Pool 관리
- 현재 활성 이상현상 관리
- 랜덤 선택
- Spawn / Despawn 호출

예시

```txt
AnomalyManager
 ├─ Pool
 ├─ ActiveAnomaly
 ├─ SelectRandom()
 ├─ SpawnCurrent()
 └─ DespawnCurrent()
```

---

# Anomaly

모든 이상현상은 동일 인터페이스 사용

```lua
local Anomaly = {}

function Anomaly:Spawn(Context)
end

function Anomaly:Despawn(Context)
end

function Anomaly:IsCleared(Context)
    return false
end

return Anomaly
```

---

# 구현 예시

## Monkey.lua

```txt
Spawn
 └─ 원숭이 생성

IsCleared
 └─ 원숭이 사망 확인

Despawn
 └─ 원숭이 제거
```

---

## MovingChair.lua

```txt
Spawn
 └─ 의자 위치 이동

IsCleared
 └─ 플레이어가 발견

Despawn
 └─ 원래 위치 복구
```

---

## FakeCamera.lua

```txt
Spawn
 └─ 가짜 CCTV 생성

IsCleared
 └─ 플레이어 파괴

Despawn
 └─ 제거
```

---

# SpawnPoint

위치 하드코딩 방지용

```txt
SpawnPoint
 ├─ Tag
 ├─ Position
 └─ Rotation
```

예시 태그

```txt
Hallway
Corner
Wall
Ceiling
BehindPlayer
Hidden
Visible
```

사용 예시

```lua
local point = Context:GetRandomSpawnPoint("Hallway")
```

---

# 이상현상 추가 방법

1. Anomalies 폴더에 Lua 파일 추가
2. Spawn / Despawn / IsCleared 구현
3. Pool 등록

```txt
Scripts/
 └─ Anomalies/
     ├─ Monkey.lua
     ├─ Ghost.lua
     ├─ MovingChair.lua
     └─ FakeCamera.lua
```

---

# 최종 구조

```txt
GameManager
 ├─ 제한시간
 ├─ 진행 상태
 └─ 승패 판정

AnomalyManager
 ├─ 이상현상 선택
 ├─ Spawn
 └─ Despawn

Anomaly
 ├─ Spawn()
 ├─ Despawn()
 └─ IsCleared()

SpawnPoint
 ├─ Tag
 ├─ Position
 └─ Rotation
```

이 구조를 기본으로 사용하면 이상현상 종류와 상관없이 Lua 파일 하나만 추가해서 확장 가능하다.