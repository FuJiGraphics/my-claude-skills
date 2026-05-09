# 아키텍처 참조 (Unity Entity 기반 게임)

코드 작성·리팩토링 전 이 문서를 먼저 확인해 불필요한 파일 탐색을 줄인다. Unity 모바일 게임에서 자주 쓰이는 Entity 계층, 상태 머신, 매니저 싱글톤, UI 라이프사이클을 한눈에 보기 위한 참조 문서다. 식별자는 모두 예시이며 프로젝트 컨벤션(접두사 `MN`, enum 접두사 `e` 등)은 별도 코드 컨벤션 문서를 따른다.

---

## Entity 계층

```
Entity (MonoBehaviour)
└── UnitEntity : Entity, IHpBar, ICCReceiver
    ├── PlayerEntity : UnitEntity, IActiveSkill
    │   └── PlayerJobEntity (JobA / JobB / JobC / JobD ...)
    │       └── Player1, Player2, ... PlayerN
    └── EnemyEntity : UnitEntity
        └── Enemy1, Enemy2, ..., EnemyBoss
ExtraEntity (MonoBehaviour, 독립)   // 보조 오브젝트 — 필요 시 별도 계층
```

- `Entity` 가 최상위 베이스, `UnitEntity` 가 HP·CC·전투 공통, 그 아래에 진영(아군/적)별 베이스, 마지막에 직업/적 종류별 구체 클래스가 온다
- 직업 베이스(`PlayerJobEntity`)는 직업 공통 동작을 모으는 중간 레이어로, 구체 클래스는 고유 동작만 가진다

### Entity (핵심 멤버)
```csharp
[SerializeField] protected eTeamType _teamType;
[SerializeField] protected eEntityType _entityType;
public Transform _ts;
public GameObject _go;

public virtual void Init();
public Vector3 GetPosition();
public eEntityType GetEntityType();
public eTeamType GetTeamType();
public void SetTeamType(eTeamType);
public virtual bool IsNonTarget();
```

### UnitEntity (핵심 멤버)
```csharp
// Fields
[SerializeField] protected StatData _statData;
[SerializeField] protected NavMeshAgent _navMeshAgent;
[SerializeField] protected Collider2D _collider;
protected UnitStateMachine _unitStateMachine;
public int _slotIdx;

// Properties
public HpBar _hpBar { get; set; }
public HitColl _hitColl { get; set; }
public CCEntity _ccEntity { get; set; }
public Stage Stage { get; }
public UnitStateMachine UnitStateMachine { get; }

// Events / Callbacks
public Action<UnitEntity> CallBackHit, CallBackDeath, CallBackCompleteAttackAnim;

// Init
public void Initialized(Stage stage, eTeamType teamType, int slotIdx, IUnitState[] states);

// Combat
public eHitResult BeHit(HitInfo hitInfo);
public void ApplyKnockback(Vector2 dir, float force, float duration);
public virtual void OnDeath();
public void Death();

// Target
public void SetTarget(UnitEntity target);
public virtual UnitEntity GetTarget();
public virtual void UpdateTargetCheck();

// Movement / NavMesh
public bool CanMoveTo(Vector3 targetPos, out NavMeshHit hit);
public void UpdateNavMeshAgent(Vector3 targetPos);
public void SetNavMeshAgentActive(bool isActive);

// Animation
public void SetAnimation(eState state, Action onComplete, string eventName = null, Action onEvent = null, float timeScale = 1f);
public void SetAnimation(eState state, bool isLoop = true, float time = 1f, bool isForce = false);

// Stat
public int GetDamage();
public int GetDefense();
public virtual float GetAttackSpeed();
public virtual float GetMoveSpeed();
public virtual float GetAttackRange();
public virtual bool CanMove();
public virtual bool CanAttack();

// CC
public CCData GetCC(eCCType type);
public virtual void AddCC(CCData ccData);

// Pool
public void PushObjectPool();
public void StageRemoveUnit();
```

### PlayerEntity (추가 멤버 예시)
```csharp
public ePlayerType _playerType;
public virtual void OnSkillExecute();    // IActiveSkill
public virtual bool IsSkillReady();
public bool UseSkill();
public virtual void CompleteSkill();
public PlayerSpecData GetPlayerSpecData();
protected virtual bool IsSkillAllowed();
protected float GetTargetDistance();
protected Vector3 GetLeaderTargetPos();
```

---

## 데이터 구조체

> 데이터 구조체는 `Assets/Scripts/Ingame/Entity/DataStruct/` 같은 별도 디렉토리에 모은다. 아래는 자주 등장하는 예시.

### StatData
```csharp
[System.Serializable]
public struct StatData
{
    public int maxHp, maxMp, damage, defense;
    public float moveSpeed, attackSpeed, attackRange;
    public void InitFromSpec(PlayerSpecData specData);
}
```

### HitInfo
```csharp
[System.Serializable]
public struct HitInfo
{
    public int _rNo;
    public double _damage;
    public eDamageFontType _fontType;
    public float _criticalPer, _criticalDamage;
    public bool _isDefenseIgnore;
    public string _hitFxName;
    public float _knockbackDuration, _knockbackForce;
    public Vector3 _knockbackDir;
    public void SetKnockback(float duration, float force, Vector3 dir);
}
```

### DamageResult
```csharp
public struct DamageResult
{
    public double originalDamage, finalDamage;
    public eDamageFontType fontType;
    public bool isCritical, hasWeakEffect;
    public double defenseApplied;
}
```

### CCData / CCEffectInfoData
```csharp
public class CCData
{
    public eCCType _type;
    public float _duration, _value, _curDuration;
}
[System.Serializable]
public struct CCEffectInfoData
{
    public eCCType _type;
    public Vector3 _localPos, _localScale;
}
```

### StatDataKeyValue
```csharp
[Serializable]
public class StatDataKeyValue
{
    public eStatType statType;
    public float val, nextVal;
}
```

---

## 상태 머신

### 인터페이스
```csharp
public interface IUnitState
{
    eUnitStateType StateType { get; }
    int Priority { get; }
    void Enter(UnitEntity unit);
    void Tick(UnitEntity unit, float deltaTime);
    void Exit(UnitEntity unit);
    bool CanTransitionTo(IUnitState nextState);
}
public abstract class BaseUnitState : IUnitState { ... }
```

### UnitStateMachine
```csharp
public class UnitStateMachine : StateMachine
{
    public eUnitStateType _lastStateType;
    public void StartMachine();
    public void AddUnitState(IUnitState state);
    public void ChangeState(eUnitStateType stateType);
    public bool TryForceStateChange(eUnitStateType stateType);
    public eUnitStateType GetCurrentStateType();
    public IUnitState GetStateByType(eUnitStateType stateType);
}
```

또는 제네릭 형태(`StateMachine<T>` + `ChangeState<TState>()`)로 구현해도 동일한 책임을 가진다.

### 상태 클래스 목록 (Priority)
| 클래스 | StateType | Priority |
|--------|-----------|----------|
| `UnitIdleState` | Idle | 0 |
| `UnitMoveState` | Move | 0 |
| `UnitAttackState` | Attack | 0 |
| `UnitSkillState` | Skill | 6 |
| `UnitSpawnState` | Spawn | 6 |
| `UnitStunState` | Stun | 5 |
| `UnitDeathState` | Death | 100 |

- Death 상태는 `CanTransitionTo → false` (되돌아올 수 없음)
- Spawn / Skill 상태는 완료 시 `CompleteSkill()` 또는 자체 전이로 빠져나간다
- 특정 스테이지 전용 상태가 필요하면 하위 디렉토리로 분리 (예: `Assets/Scripts/Ingame/State/StageX/`)

---

## 대미지 시스템

```csharp
// 파이프라인: BeHit → DamageCalculator → HpBar → Death
public static class DamageCalculator
{
    public static DamageResult CalculateDamage(HitInfo hitInfo, UnitEntity target);
}

public class DamageSystem : MonoBehaviour  // 싱글톤
{
    public static DamageSystem Instance { get; }
    public void SetDamageProcessor(IDamageProcessor processor);
    public DamageResult ProcessDamage(HitInfo hitInfo, UnitEntity target);
    public void SetGlobalDamageMultiplier(float multiplier);
}

public interface IDamageProcessor
{
    DamageResult ProcessDamage(HitInfo hitInfo, UnitEntity target);
}
// 구현체 예: StandardDamageProcessor, CriticalDamageProcessor
```

---

## 투사체 (Projectile)

### 베이스
```csharp
// Assets/Scripts/Ingame/Projectile/
public abstract class Projectile : MonoBehaviour
{
    [SerializeField] protected AtkColl _atkColl;
    public Transform _ts;
    public GameObject _go;
    protected UnitEntity _ownerEntity;
    protected HitInfo _hitInfo;
    protected float _speed, _impactRange;
    protected Vector3 _startPos, _direction;
    protected bool _isActive;

    public virtual void Launch(UnitEntity owner, Vector3 direction, HitInfo hitInfo, float speed, int maxHitCount);
    public void SetHitCallBack(Action<UnitEntity, eHitResult, int> hitCallBack);
    protected abstract void UpdateMove();
    protected virtual void OnHitEnemy(UnitEntity target);
    protected void BehitEnemy(UnitEntity target);
    protected virtual void ReturnToPool();
}
```

### 하위 클래스 예시
| 클래스 | 특징 |
|--------|------|
| `ProjectileStraight` | 직선 이동 |
| `ProjectileCurve` | 포물선 (`LaunchCurve(owner, targetPos, arcHeight, hitInfo, duration, maxHit)`) |
| `ProjectileHoming` | 유도 → 직선 전환 (`LaunchHoming(owner, hitInfo, speed, maxHit, speedFactor, distMinMax, homingTimeMinMax)`) |
| `ProjectileWobble` | 흔들림 이동 |

---

## Stage 시스템

```csharp
// Assets/Scripts/Ingame/Stage/
public class Stage : MonoBehaviour
{
    public eStageType _stageType;
    public List<UnitEntity> _myUnits, _enemyUnits;
    public List<ExtraEntity> _extraEntities;

    public UnitEntity GetLeaderUnit();
    public UnitEntity GetTarget(UnitEntity unit, eUnitFindType findType);
    public UnitEntity GetAroundRandomTarget(UnitEntity unit, float range);
    public virtual void StartStage();
    public virtual void OnMyUnitAllDeath();
    public virtual void OnEnemyAllDeath();
    public void AddUnit(UnitEntity unit);
    public void RemoveUnit(UnitEntity unit);
    public void Tick(float deltaTime);
    public int GetMyUnitCount();
    public int GetEnemyUnitCount();
}
// 구현체 예: Stage1, Stage2, ...
```

> 프로젝트에 따라 `Zone`, `Battle`, `Room` 등 다른 이름을 쓰지만 책임은 동일하다.

---

## 매니저

매니저는 `MonoSingleton<T>` 상속 또는 `Awake`에서 `ins` 필드 직접 설정. 접두사는 프로젝트 컨벤션을 따른다(예: `MN<Module>`). 아래는 일반적인 역할 분담.

| 분류 | 예시 클래스 | 접근자 예시 | 책임 |
|------|------------|------------|------|
| 게임 시작 | `GameManager` | `GameManager.Instance` | 게임 시작, Stage 초기화 |
| 스테이지 | `MNStage` | `MNStage.ins` | Stage 배열·전환 관리 |
| 게임 전역 | `MNGame` | `MNGame.ins` | 게임 전역 상태, 진행도 |
| 스펙 | `MNSpec` | `MNSpec.ins` + static 프로퍼티 | 스펙 데이터 로드 (원격 → 로컬 캐시 → ScriptableObject) |
| 리소스 | `MNRes` | `MNRes.ins` | 리소스 로드 (Addressables 래퍼) |
| 인증 | `MNAuth` | `MNAuth.ins` | 로그인 / 인증 |
| 유저 데이터 | `MNUserData` | `MNUserData.Instance` / `MNUserData.UserData` | 유저 데이터 저장/로드 |
| 초기화 시퀀스 | `MNSession` | `MNSession.Instance` | 부팅 비동기 시퀀스 |
| UI | `MNUi` | `MNUi.ins` | Popup / Content 생명주기 |

### 스펙 매니저 접근 패턴
```csharp
MNSpec.Player        // PlayerSpecScriptableData
MNSpec.Equip         // EquipSpecScriptableData
MNSpec.Item          // ItemSpecScriptableData
MNSpec.StatList      // StatListSpecScriptableData
MNSpec.Option        // OptionSpecScriptableData
MNSpec.Get<T>()      // 제네릭 접근
MNSpec.GetPlayerSpecDataStatic(ePlayerType playerType)
```

### Session 초기화 흐름 (예시)
```csharp
await SetupAsync(ct);        // 기본 설정
await LoginAsync(ct);        // 인증
await LoadSpecAsync(ct);     // 스펙 다운로드
await LoadUserDataAsync(ct); // 유저 데이터
```

---

## UI 라이프사이클

- **Popup (`BasePopup` 계열)** — Stack 기반 관리, DOTween Fade in/out, Escape 키로 최상위 팝업 닫기
- **Content (`BaseContent` 계열)** — 탭 기반 영구 표시 화면용
- **Controller (`BaseUiController` 계열)** — View ↔ 데이터 연결 레이어 (선택)
- 프리팹은 `Assets/Prefabs/UI/Popup`, `Assets/Prefabs/UI/Content` 같은 위치에 두고 **Addressables**로 동적 로드/언로드한다

```csharp
public class MyPopup : BasePopup
{
    public override void OnOpen()  { /* ... */ }
    public override void OnClose() { /* ... */ }
}
```

---

## 인터페이스 (예시)

```csharp
public interface IActiveSkill
{
    void OnSkillExecute();
    bool IsSkillReady();
    bool UseSkill();
    void CompleteSkill();
}
public interface IHpBar     { HpBar _hpBar { get; set; } }
public interface ICCReceiver { void AddCC(CCData ccData); }
public interface IDamageProcessor { DamageResult ProcessDamage(HitInfo hitInfo, UnitEntity target); }
```

---

## 핵심 Enum (예시)

> enum 접두사는 `e`를 사용한다 (코드 컨벤션 참조).

```csharp
enum eTeamType       { My, Enemy }
enum eEntityType     { Player, Enemy, Extra }
enum eStageType      { Stage1, Stage2, Stage3, Stage4 }
enum eUnitStateType  { None, Idle, Move, Attack, Skill, Stun, Death, Spawn }
enum eState          { idle, run, attack, skill, hit, ... }   // 애니메이션 상태
enum eUnitFindType   { Near, Far, Random }
enum eCCType         { Stun, FireDot, Slow, Freeze, IgnoreDefense, Madness, Weak }
enum eDamageFontType { Normal, Critical, Dot }
enum eHitResult      { Hit, Death }
enum eStatType       { ... }   // StatDataKeyValue 키
```

---

## 핵심 흐름 요약

### 유닛 대미지
```
UnitEntity.BeHit(HitInfo)
→ DamageCalculator.CalculateDamage()  [크리티컬 · 방어 · 상태이상]
→ HpBar.AddValue(-damage)
→ isDead? → Death() → UnitDeathState
```

### 투사체 히트
```
Projectile.UpdateMove() → AtkColl 충돌
→ OnHitEnemy(target) → BehitEnemy(target) → target.BeHit(hitInfo)
→ maxHitCount 도달 → ReturnToPool()
```

### 스킬 실행
```
PlayerEntity.UseSkill()  [IsSkillReady() && IsSkillAllowed()]
→ UnitStateMachine.ChangeState(Skill)
→ UnitSkillState.Enter() → SetAnimation(skill, ...)
→ OnSkillExecute() [히트 판정 / 투사체 발사]
→ CompleteSkill() → UnitSkillState.CompleteSkill() → 상태 복귀
```

### Stage 초기화
```
GameManager.Start() → MNStage.Initialize()
→ Stage.StartStage() → UnitEntity.Initialized(stage, team, slotIdx, states)
→ UnitStateMachine.StartMachine() → UnitSpawnState
```
