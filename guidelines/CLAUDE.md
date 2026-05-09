# 프로젝트 개요 (템플릿)

> 이 섹션은 프로젝트별로 채워 넣는다. 아래는 placeholder.

- **장르**: (예: 모바일 액션, RPG, 퍼즐 등)
- **엔진**: Unity (URP / Built-in / HDRP 중 택1, 사용 중인 2D/3D 파이프라인 명시)
- **빌드 대상**: (예: Android, iOS, Standalone)
- **주요 씬**: `Assets/Scenes/<MainScene>.unity`

---

## 참조 문서 (작업 전 먼저 확인)

작업을 진행하기 전, 관련있는 문서를 탐색한다. 프로젝트별로 아래 표를 갱신한다.

| 문서 | 대상 영역 |
|------|----------|
| Architecture | 데이터 구조체 시그니처, 핵심 흐름 요약 |
| CodeConvention | 변수명, 접두사, 포매팅 규칙 |
| SpecData | 스펙 데이터 파이프라인, 외부 시트/DB 연계, 새 스펙 추가 절차 |
| Refactoring | 코드 정리 시 참고 |
| UserData | 유저 데이터 저장소 구조, 직렬화 패턴, 새 데이터 추가 절차 |

---

## 공통 규칙

### 라이프사이클 베이스 컴포넌트 — Cleanup override 강제

프로젝트가 정의한 라이프사이클 베이스(예: `MonoBaseSkill`, `MonoBaseEntity` 등)를 상속하는 모든 클래스는 **반드시 `Cleanup()` 오버라이드를 추가**한다.

- 시그니처: `public override void Cleanup()`
- 자식 클래스 자체의 비동기 자원(트윈 / 코루틴 / 콜백 / 상태 플래그)을 먼저 정리한 뒤 마지막 줄에 `base.Cleanup()` 호출
- 정리할 자원이 없는 경우에도 override를 생략하지 않고 `base.Cleanup()`만 호출하는 빈 override를 둔다 (패턴 강제)
- 신규 자식 클래스를 만들 때부터 위 규칙을 자동 적용한다

```csharp
public override void Cleanup()
{
    _someTween?.Kill();
    _someTween = null;

    base.Cleanup();
}
```

### 인게임 좌표 규칙 (2D 프로젝트의 Z 포지션)

2D 게임플레이에서 모든 인게임 오브젝트(유닛, 발사체, 이펙트, 인게임 UI 오브젝트 등)의 **기본 z포지션은 0**이다. 사용자가 명시적으로 z값을 지정하지 않은 한 z=0을 유지한다.

- **이동/위치 갱신 시** NavMesh, Rigidbody, 트윈 등으로 z가 드리프트되지 않도록 주의
- 드리프트 우려가 있는 클래스는 `LateUpdate`에서 `transform.position.z = 0f`을 강제
- z 레이어링이 정말 필요한 경우(예: SortingOrder 대체용)는 명시적으로 요청·합의된 경우에만 사용

```csharp
private void LateUpdate()
{
    var pos = transform.position;
    if (pos.z != 0f)
    {
        pos.z = 0f;
        transform.position = pos;
    }
}
```

---

## 디렉토리 구조 (권장 컨벤션)

> 실제 루트 폴더명(`Assets/Scripts` vs `Assets/A_Scripts` 등)은 프로젝트별로 정한다. 중요한 것은 **역할별 분리**이다.

```
Assets/
├── Scripts/
│   ├── Managers/           # 싱글톤 매니저 (MN* 또는 프로젝트 접두사)
│   │   └── Pool/           # 오브젝트 풀 매니저
│   ├── Ingame/
│   │   ├── Entity/         # Entity → UnitEntity → 직업/적 베이스 → 구체
│   │   │   ├── DataStruct/ # HitInfo, StatData 등 데이터 구조체
│   │   │   ├── Player/     # 플레이어 직업/타입 베이스 + 구체 구현
│   │   │   └── Enemy/      # 일반/보스 적 구체 구현
│   │   ├── State/          # StateMachine 상태 (Idle/Move/Attack/Skill/Death/Stun)
│   │   ├── Core/           # DamageSystem, Calculator, Utils
│   │   ├── Collider/       # 공격/피격 콜라이더
│   │   ├── Projectile/     # 발사체 베이스 + 변형(Straight/Curve/Homing 등)
│   │   ├── Interfaces/     # 공용 인터페이스 (IHpBar, ICCReceiver 등)
│   │   ├── UnitBar/        # HP바 등 유닛 부착 UI 컴포넌트
│   │   └── Stage/          # 스테이지/Zone 로직
│   ├── UI/                 # BaseView / BaseController 계열
│   ├── Skill/              # 스킬 구현
│   ├── Animation/
│   ├── Camera/
│   ├── Data/               # 상수, 게임 데이터 정의
│   ├── Components/
│   └── Editor/             # 에디터 전용 유틸
├── Prefabs/
│   ├── UI/                 # Addressable UI 프리팹 (Popup/Content)
│   ├── Player/
│   ├── Enemy/
│   ├── Bg/
│   └── Skills/
├── Effects/                # VFX 리소스
├── Res/                    # 애니메이션, UI 이미지, 타일맵 등
├── Data/
│   ├── SpecJson/
│   ├── UserData/
│   └── Haptics/
└── Scenes/
```

---

## 아키텍처 패턴

### 매니저 (싱글톤)

`MonoSingleton<T>` 상속 또는 `Awake`에서 `ins` 필드 직접 설정. 접두사는 프로젝트 컨벤션에 맞춘다(예: `MN<Module>`).

| 분류 | 책임 |
|------|------|
| UI 매니저 | Popup/Content 생명주기, Addressables 동적 로드 |
| Game 매니저 | 게임 전역 상태, 진행도 |
| Spec 매니저 | 스펙 데이터 로드 (원격 → 로컬 캐시 → ScriptableObject) |
| Resource 매니저 | 리소스 로드 (Addressables 래퍼) |
| Auth 매니저 | 인증 |
| UserData 매니저 | 유저 데이터 저장/로드 |
| Stage 매니저 | 스테이지/Zone 초기화·전환 |

```csharp
public class SomeManager : MonoSingleton<SomeManager>
{
    // ...
}
```

### 엔티티 계층

```
Entity
└── UnitEntity
    ├── PlayerEntity
    │   └── PlayerJobEntity (직업 베이스: Archer/Mage/Warrior 등)
    │       └── Player1, Player2 ... (구체 구현)
    └── EnemyEntity
        └── Enemy1, Enemy2 ..., EnemyBoss
```

- 공통 스탯·HP·CC 처리는 `UnitEntity` 레벨에 둔다
- 직업/적 카테고리별 공통 동작은 중간 베이스(`PlayerJobEntity` / `EnemyEntity`)에 둔다
- 개별 캐릭터·몬스터 고유 동작만 가장 하위 구체 클래스에 둔다

### 상태 머신

- `StateMachine<T>` (Generic) — `ChangeState<TState>()` 로 전환
- 표준 상태 세트: `UnitIdleState` / `UnitMoveState` / `UnitAttackState` / `UnitSkillState` / `UnitSpawnState` / `UnitDeathState` / `UnitStunState`
- 특정 스테이지 전용 상태가 필요하면 별도 폴더로 분리 (예: `State/StageX/`)

### UI 시스템

- **Popup (`BaseView` 계열)**: 베이스 팝업 클래스 상속 → UI 매니저가 Stack으로 관리, DOTween Fade in/out
- **Content (`BaseContent` 계열)**: 탭 기반 영구 표시 화면용 베이스
- **Controller (`BaseController` 계열)**: View와 데이터를 잇는 컨트롤러 레이어 (선택)
- Addressables로 동적 로드/언로드, Escape 키로 최상위 팝업 닫기

```csharp
public class MyPopup : BaseView
{
    public override void OnOpen() { /* ... */ }
    public override void OnClose() { /* ... */ }
}
```

---

## 주요 패키지 (참고 버전)

> 새 프로젝트에서 사용한 실제 버전으로 갱신.

| 패키지 | 비고 |
|--------|------|
| Addressables | 동적 리소스 로드의 표준 |
| DOTween | 트윈 — 베이스 컴포넌트 Cleanup에서 반드시 `Kill()` |
| URP | 2D Renderer 사용 시 Sorting Layer 정리 |
| Input System | 신 입력 시스템 |
| 2D Animation | 본 기반 2D |
| Spine Runtime | 외부 스파인 애니메이션 |
| AI Navigation | NavMesh — z 드리프트 주의 |
| NewtonSoft JSON | 직렬화 |

---

## Unity CLI 연동 (옵션)

`unity-cli` 또는 동등 도구를 통해 터미널에서 Unity Editor를 제어할 수 있다. 코드 수정 후 컴파일 에러 확인, 플레이 모드 실행, 스크린샷 캡처 등에 활용한다. 환경별 설정은 프로젝트 README 참조.
