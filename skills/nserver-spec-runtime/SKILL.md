---
name: nserver-spec-runtime
description: NServer 패키지(`Brainworks.NServer`)의 spec 데이터를 인게임 코드에 주입할 때 따라야 할 영구 지침. NSpecData/NSession 이 이미 떠안고 있는 책임을 프로젝트 측에 중복 구현하지 않기, DTO 1:1 미러 wrapper 만들지 않기, 헤드리스 순수성 경계 지키기, MN* / N* 접두사 컨벤션, spec subclass Init() 패턴, 헤드리스 룰 동적 주입 패턴을 강제. 사용자가 "스펙 데이터 주입", "spec 데이터 인게임에", "헤드리스에 spec 적용", "이 spec 을 게임에 어떻게 연결", "이 시트를 게임에 반영", "MNSpec / NSpecData / NSession", "GeniusSpec / GeniusUserData" 등으로 NServer 기반 Unity 프로젝트(The-Genius / TeamBattle 등 Brainworks.NServer 패키지가 설치된 프로젝트)에서 시트 → 인게임 흐름을 만들거나 손볼 때, 또는 `Assets/A_Data/SpecJson/` / `Assets/A_Scripts/Server/` / `*SpecScriptableData.cs` 파일을 다룰 때 자동 적용. 자매 skill `nserver-spec-data` 가 시트 디자인 컨벤션을 다룬다면 이 skill 은 그 시트로 만들어진 .asset 을 런타임 게임 코드에 어떻게 흘려넣을지를 다룬다.
---

# nserver-spec-runtime

NServer 의 자동 생성된 SpecScriptableData 를 인게임 코드에 흘려넣을 때 사용한다. 자매 skill **`nserver-spec-data`** 는 시트 디자인 컨벤션, 이 skill 은 그 결과물인 `.asset` 을 런타임 코드에 wiring 하는 단계 — 둘은 겹치지 않는다.

**핵심 원칙: NServer 패키지(`Packages/com.brainworks.nserver/`) 는 사용자가 직접 만든 SDK 다.** TeamBattle 의 프로젝트 측 매니저(`MNSpec`/`MNSession`/`ServerSpecDataExtensions`) 를 재사용 가능한 패키지로 추출한 것. 그래서 새 기능이 어디 있어야 할지 애매하면 **프로젝트에 또 만들지 말고 NServer 에 추가**하는 쪽이 맞다.

---

## 1. NSpecData 가 이미 갖춘 것 vs 빠진 것

`NSpecData` (정적 게이트웨이로 `NServer.SpecData` 접근) 는 TeamBattle `MNSpec` 로직의 ~80% 가 이미 이식돼 있다.

**이미 패키지에 있음 — 다시 만들지 말 것:**
- `_specList` (List&lt;INSpecData&gt;)
- `Register / RegisterRange / Clear`
- `LoadSpecAsync(ct, progress)` — Firebase Storage 다운로드 + 버전 비교 + PlayerPrefs 캐시 + 각 spec 의 `PopulateFromJson` 자동 호출
- `LoadCachedRows(specName)`
- csv 파싱 헬퍼 (`ParseCsv`, `SplitCsvLine`)

**패키지에 흡수 완료된 것 (The-Genius 에서 적용 끝):**
- `Get<T>()` 제너릭 + `_byType` Type-keyed dict 캐시 — NSpecData 자체 멤버.
- `InitAll()` — 등록된 spec 전부에 `spec.Init()` 1회 호출. 인스펙터 시드 데이터용. 원격 `PopulateFromJson` 은 이미 자동으로 Init 호출.
- `PushBundleSpecsToCache()` — 번들 SO `_list` → PlayerPrefs 시드 (오프라인-퍼스트).
- `INSpecData` 인터페이스에 `Init()` / `SerializeToJArray()` 노출.

**아직 패키지에 빠져있고 추가는 신중히 결정할 것:**
- spec asset 자동 발견 (`Resources.LoadAll<SpecScriptableData>(폴더)` 또는 `AssetDatabase.FindAssets`). The-Genius 는 prefab 인스펙터 와이어링 + RuntimeInitializeOnLoadMethod 패턴(§7)으로 해결했으므로 자동 발견은 불필요했음. 다른 프로젝트도 그 길로 가는 게 단순.

**중요**: `NSpecBootstrapSettings` 같은 **별도 ScriptableObject 자료형을 만들지 말 것.** NSpecData 가 plain 클래스라 인스펙터 직렬화는 안 되지만, 그 인스펙터 보관 책임은 프로젝트 측 얇은 MonoBehaviour 호스트 (예: `MNSpec`, §6.2) 에 위임한다. 사용자 명시: "NSpecData 얘로 일원화 가능한 건 다 일원화 하면되고 굳이 새로운거 만들 필요는 없음".

---

## 2. NSession 핵심 API

`NSession` (정적 게이트웨이 `NServer.Session`) 은 TeamBattle `MNSession` 의 포팅.

```csharp
// 한 번에 다 처리하는 idempotent one-shot. 인게임 씬 직접 시작 시 fallback bootstrap 이 부르면 됨.
public async UniTask SetupAsync<T>(
    T defaultUserData,
    IEnumerable<INSpecData> specs = null,
    Action onConflictDetected = null,
    Action<bool> onShutdown = null,
    CancellationToken ct = default) where T : class
// 내부: if _isReady return; → InitAsync(specs) → LoginAsync → LoadSpecAsync → SetupCurrentUserDataAsync → SetReady

// 인트로 state machine 이 부분 단계로 부르는 형태
public async UniTask InitAsync(
    IEnumerable<INSpecData> specs = null,  // null 이 아니면 Clear() + RegisterRange(specs)
    CancellationToken ct = default,
    IProgress<float> progress = null)
```

**둘 다 idempotent.** 여러 곳에서 불려도 안전 — Intro state machine + 인게임 씬 fallback 양쪽에서 부담 없이 호출 가능.

`SpecScriptableData.PopulateFromJson(JArray)` 는 `_list` 역직렬화 후 자동으로 `Init()` 을 부른다. 그래서 원격 갱신 시엔 자동, 인스펙터 시드값엔 부트 시 1회 명시 호출 필요.

---

## 3. 절대 하지 말 것

### 3.1 프로젝트 측 매니저는 "얇은 부트 호스트" 만 — NSpecData 책임 중복 X

`Get<T>`, `_cachedSpecDic`, `RegisterRange` wrapping, `PushBundleSpecsToCache` 같은 건 NSpecData 가 이미 갖고 있으니 **프로젝트 측에서 다시 구현하지 말 것**. 정적 편의 속성 (`MNSpec.Puzzle` 같은 것) 도 두지 말 것 — `GeniusSpec.Puzzle` 정적 헬퍼가 그 역할.

대화 기록: 사용자가 명시적으로 거부함 — "MNGeniusSpec 얘는 그냥 아예 필요없는거지 임마 니가 의도를 제대로 파악 못하고 중복된 애를 생성한거잖아".

**프로젝트 측에 둘 수 있는 것:**

(a) 프로젝트-타입 정적 편의 속성을 가진 얇은 정적 헬퍼 클래스
```csharp
public static class GeniusSpec  // MN 접두사 X — MonoBehaviour 아님
{
    public static GeniusPuzzleSpecScriptableData Puzzle => NServer.SpecData.Get<GeniusPuzzleSpecScriptableData>();
    public static GeniusRulesSpecScriptableData  Rules  => NServer.SpecData.Get<GeniusRulesSpecScriptableData>();
    public static GeniusScoreBoardSpecScriptableData ScoreBoard => NServer.SpecData.Get<GeniusScoreBoardSpecScriptableData>();
}
```

(b) 프로젝트 specific csv → 런타임 객체 빌더 메서드 (헤드리스 게임 데이터로 변환)
```csharp
public static class GeniusSpec  // 위와 같은 클래스
{
    public static PuzzleData     BuildPuzzleData(int level, int problem) { ... }
    public static ScoreBoardData BuildScoreBoardData(string boardId = "default") { ... }
}
```

(c) **얇은 부트 호스트 `MNSpec`** (§6.2 참조) — 인스펙터 spec list 보관 + 자동 부트 트리거만. 정적 편의 속성/Get<T>/_cachedSpecDic/InitLocalSpecData 같은 NSpecData 와 중복되는 건 절대 두지 말 것.

### 3.2 DTO wrapper 만들지 말 것

spec row 의 필드를 **같은 primitive 타입으로 1:1 미러링하는 plain POCO** 를 만들지 말 것. spec row 자체(예: `GeniusRulesSpecData`) 가 이미 namespace 없는 plain POCO 라 NServer/Unity 의존성이 0이고, 헤드리스가 직접 받아도 됨.

대화 기록: 사용자 명시 거부 — "왜 굳이 dto를 만드는거야? 복잡하게".

```csharp
// ❌ 하지 마라
public sealed class GeniusRulesData    // 이미 GeniusRulesSpecData 가 같은 5필드를 갖고 있음
{
    public int turnTimeLimitSeconds;
    public int onePointInitialScoreTokens;
    // ...
}

// ✅ 그냥 spec POCO 직접 받기
public static void Apply(GeniusRulesSpecData rules) { ... }
```

### 3.3 NSpecData 옆에 새 wrapper 클래스 / 새 ScriptableObject 자료형 만들지 말 것

NSpecData 는 plain 클래스(MonoBehaviour/SO 아님)라 인스펙터 직렬화가 안 되지만, 그렇다고 `NSpecBootstrapSettings` 같은 **새 ScriptableObject 보관소 자료형** 을 만드는 게 정답은 아니다. 자동 발견(`Resources.LoadAll<SpecScriptableData>` / `AssetDatabase.FindAssets("t:SpecScriptableData")`) + EditorPrefs 토글 정도로 별도 자료 스키마 없이 처리한다.

대화 기록: 사용자 명시 — "NSpecData 얘로 일원화 가능한 건 다 일원화 하면되고 굳이 새로운거 만들 필요는 없음".

원칙: **NSpecData 안에 흡수할 수 있으면 무조건 그쪽으로.** 새 클래스/타입 추가는 NSpecData 가 책임지기 정말로 어색한 영역(예: 단순 EditorWindow 한 파일) 에 한정.

### 3.4 헤드리스 순수성 경계 깨지 말 것

`Assets/A_Scripts/Ingame/Headless/` 는 `Brainworks.NServer.*` / `UnityEngine.*` 의존성 없는 순수 데이터·규칙 레이어로 의도됨 (Debug.Log 정도만 예외).

- spec POCO 행 (예: `GeniusRulesSpecData` — namespace 없는 plain POCO) → **OK 받아도 됨** (자체 의존성 없음).
- `SpecScriptableData` 타입 (ScriptableObject), `NServer.SpecData.X` 호출 → **헤드리스 파일에 들이지 말 것**.

spec → 헤드리스 변환은 프로젝트 측 정적 헬퍼의 빌더에서 해야 함 (3.1.b).

---

## 4. 명명 컨벤션

| 접두사 | 의미 | 예 |
|---|---|---|
| `MN*` | MonoBehaviour / MonoSingleton 매니저 인스턴스 — 씬 GameObject 라이프사이클이 진짜로 필요한 경우만 | `MNUi`, `MNRes` |
| `N*` | 패키지 레벨 non-MonoBehaviour 서비스 | `NSpecData`, `NSession`, `NUserData` |
| (접두사 없음) | 프로젝트 측 정적 헬퍼 — Mono/싱글톤 X | `GeniusSpec`, `TeamBattleSpec` |

`MNGeniusSpec` 같은 이름은 함정: MN 은 MonoBehaviour 매니저 의미인데 정적 헬퍼면 GameObject 가 없으므로 MN 빼야 한다.

---

## 5. spec subclass Init() 오버라이드 패턴

```csharp
public class GeniusPuzzleSpecScriptableData : SpecScriptableData
{
    public List<GeniusPuzzleSpecData> _list;  // 시트 1:1 DTO — 건드리지 말 것

    private Dictionary<(int level, int problem), GeniusPuzzleSpecData> _byLevelProblem;
    private Dictionary<int, GeniusPuzzleSpecData> _byPuzzleId;

    public override void Init()
    {
        base.Init();  // 항상 먼저 호출
        _byLevelProblem = new();
        _byPuzzleId = new();
        if (_list == null) return;
        foreach (var row in _list)
        {
            _byLevelProblem[(row.levelNumber, row.problemNumber)] = row;
            _byPuzzleId[row.puzzleId] = row;
        }
    }

    public GeniusPuzzleSpecData GetByLevelProblem(int level, int problem)
        => _byLevelProblem != null && _byLevelProblem.TryGetValue((level, problem), out var r) ? r : null;
}
```

규칙:
- `base.Init()` 먼저.
- `_byId` / `_byKey` / `_byCompoundKey` 같은 secondary 인덱스 dict 빌드.
- 문자열로 인코딩된 enum 은 `Enum.TryParse(text, out e)` 로 파싱.
- **spec row 의 `_list` 필드 구조는 시트와 1:1 유지** — 파싱된 런타임 형태(예: `Dictionary<CellCoord, ...>`) 를 spec row 안에 캐싱하지 말고 빌더로 미룰 것. 자동 생성 `GoogleSheetSpecImporter` 가 재실행돼도 커스텀 코드가 살아남게.

---

## 6. 헤드리스 룰 동적 주입 패턴

`GeniusPuzzleRules` 같은 "static class with const ints" 패턴을 spec 시트에서 주입 가능하게 바꿀 때:

```csharp
public static class GeniusPuzzleRules
{
    // 물리 고정 상수 — const 그대로
    public const int MinHeight = 1;
    public const int MaxHeight = 4;

    // 디자이너 튜닝 가능한 것들 — static field 로 변경, 디폴트값은 옛 const 값 유지
    public static int TurnTimeLimitSeconds = 60;
    public static int OnePointInitialScoreTokens = 5;
    public static int OnePointSolvedPuzzleLimit = 3;
    public static int MultiPointPieceCnt = 2;
    public static int MultiPointMaxCorrectTokensPerTurn = 6;

    // null-guard + 5/N 필드 복사. spec POCO 를 직접 받음 (DTO 래퍼 X)
    public static void Apply(GeniusRulesSpecData rules)
    {
        if (rules == null) return;
        TurnTimeLimitSeconds = rules.turnTimeLimitSeconds;
        OnePointInitialScoreTokens = rules.onePointInitialScoreTokens;
        // ...
    }
}
```

세션 진입점에 optional 파라미터 끼워 넣고 `StartCore` funnel 첫 줄에서 `Apply` 호출:

```csharp
public void StartOnePoint(PuzzleData puzzle, IEnumerable<PlayerData> players, GeniusRulesSpecData rules = null)
    => StartCore(GeniusGameMode.OnePoint, puzzle, players, null, rules);

private void StartCore(..., GeniusRulesSpecData rules)
{
    GeniusPuzzleRules.Apply(rules);  // ← 첫 줄. 이후 모든 정적 필드 read 는 갱신된 값을 봄.
    // ... 기존 본문
}
```

`const int` → `static int` 변경은 호출자 syntax 에 영향 없음 (`GeniusPuzzleRules.TurnTimeLimitSeconds` 는 양쪽 다 동일 접근).

---

## 7. 부트스트랩 흐름 기대치

사용자는 **개발 단계에 인트로 씬을 거치지 않고 어떤 씬에서든 바로 플레이 모드를 시작** 하길 원한다 (자주 쓰는 워크플로우). 그래서 spec 등록은 EntryPoint state-machine 에 의존하면 안 된다.

### 7.1 prefab + RuntimeInitializeOnLoadMethod 패턴 (정답)

프로젝트마다 얇은 부트 호스트 MonoBehaviour `MNSpec` 을 두고, 그 prefab 을 `Resources/Bootstrap/MNSpec.prefab` 에 배치, 코드로 자동 인스턴스화한다. 어떤 씬에서 Play 시작하든 첫 씬 로드 전에 spec 등록 끝.

```csharp
public sealed class MNSpec : MonoSingleton<MNSpec>
{
    [SerializeField] private List<SpecScriptableData> _specData = new();

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    private static void Bootstrap()
    {
        var prefab = Resources.Load<GameObject>("Bootstrap/MNSpec");
        if (prefab == null) { Debug.LogWarning("..."); return; }
        var go = Instantiate(prefab);
        go.name = "MNSpec";
    }

    protected override void Awake()
    {
        base.Awake();                  // 중복 가드 + DontDestroyOnLoad
        if (Instance != this) return;  // 중복 인스턴스 즉시 종료
        NServer.SpecData.RegisterRange(_specData);
        NServer.SpecData.InitAll();
        NServer.SpecData.PushBundleSpecsToCache();
    }
}
```

prefab 인스펙터에 spec asset 들을 와이어링. 씬에는 prefab 인스턴스를 두지 않는다 (RuntimeInitializeOnLoadMethod 가 자동 인스턴스화). 인트로 씬에서 시작하든 인게임 씬 직접 시작하든 동일하게 동작.

**왜 prefab + RuntimeInitializeOnLoadMethod 인가?**:
- TeamBattle 의 "씬마다 prefab 인스턴스 박기" 패턴은 새 씬을 만들 때마다 사람이 prefab 박는 작업을 잊을 위험.
- Resources/ 안의 prefab 을 코드가 자동 인스턴스화하면 그 위험이 0. 사용자가 새 씬을 만들어도 자동 작동.

### 7.2 EntryPoint 와의 관계

EntryPoint state machine 의 `NServer.Session.InitAsync(ct, progress)` 는 specs 인자 없이 호출. NSession.InitAsync 의 동작은 specs 가 null 이면 이미 등록된 _specList 를 건드리지 않으므로 (`Clear + RegisterRange` 는 non-null 시만), MNSpec.Awake 가 먼저 등록한 spec list 가 그대로 유지된다.

EntryPoint 의 `OnLoadSpecAsync` 가 부르는 `LoadSpecAsync(ct, progress)` 는 _specList 의 spec 들에 대해 Firebase 갱신본 다운로드 → `PopulateFromJson` → 자동 `Init()` 재호출 → 인덱스 재빌드.

**EntryPoint 에 spec 관련 코드를 박지 말 것** — 인스펙터 `[SerializeField] List<SpecScriptableData>` 도, OnInitAsync 에서 `InitAll/PushBundleSpecsToCache` 호출도 X. 모두 MNSpec.Awake 가 처리한다. EntryPoint 는 NServer.Session 진행 단계만 책임.

### 7.3 "Firebase 갱신본" 의 의미

`NServer.SpecData.LoadSpecAsync()` 가 Firebase Storage 의 시트 csv 를 받아 `PopulateFromJson` 으로 spec `_list` 를 덮어씀 — 디자이너가 시트에서 막 publish 한 변경분이 곧 "갱신본". 인트로 씬을 거치지 않으면 그 단계가 스킵돼 spec asset 의 `_list` 는 임포터가 마지막에 박아둔 시점의 데이터만 들고 있다. `NSession.SetupAsync` 를 fire-and-forget 으로 어디선가 부르면 비동기로 갱신본 다운로드 진행 — 영구히 못 받는 건 아님.

---

## 8. Out-of-scope 가드레일 (사용자가 명시적으로 요청하지 않는 한 default 거부)

- **이어하기 / mid-game save** — `GeniusGameSession` 같은 헤드리스 세션 런타임 상태를 `GeniusUserData` 같은 유저 데이터로 스냅샷 직렬화는 별도 PR.
- **현재 시트에 컬럼 없는 clue 타입** — 헤드리스에 `RangeSumClue` / `ExtremumClue` (Lowest/Highest) / `LetterFormulaClue` 타입이 있어도 시트 컬럼이 없으면 빌더에서 무시. 시트에 컬럼 추가 시 빌더 확장.
- **멀티 보드** — 시트가 `boardId="default"` 하나만 갖고 있으면 빌더는 그 하나만 처리. `BuildScoreBoardData(string)` 시그니처는 미래 대비로 열어두되 다중 보드 로직은 별도.
- **헤드리스 안의 데이터 클래스를 spec/유저데이터로 옮기기** — `CellCoord` / `NumberToken` / `*Clue` 등은 순수 값 타입, `TokenInventory` / `PlayerData` / `ScorePieceData` 는 세션 런타임 상태. 둘 다 헤드리스에 머물러야 정상이고 spec/유저데이터로 옮길 대상 아님. (정적 정의 부분은 이미 spec 으로 빠져있음.)

---

## 9. 작업 진입 시 체크리스트

새 spec 데이터를 인게임에 주입하라는 요청을 받으면:

1. **시트가 이미 있는가?** 없으면 자매 skill `nserver-spec-data` 컨벤션을 먼저 따라 시트 디자인 → 자동 생성 트리거.
2. **`*SpecScriptableData.cs` 가 자동 생성됐는가?** 됐다면 `Init()` 오버라이드 + secondary index dict 추가 (섹션 5).
3. **인게임에서 어떤 형태로 쓰이는가?** 헤드리스 강타입 객체 빌드가 필요하면 프로젝트 측 정적 헬퍼(`<Project>Spec` 클래스) 의 빌더 메서드로 csv/enum 파싱 (섹션 3.1.b). spec row 그대로 쓰는 단순 케이스면 정적 편의 속성만 (`<Project>Spec.X => NSpec.Get<...>()`).
4. **룰 상수 시트가 있는가?** 헤드리스 정적 룰 클래스의 `const` → `static field` 변환 + `Apply(spec POCO)` 메서드 추가 + `StartCore` funnel 에서 호출 (섹션 6).
5. **부트스트랩에 등록되는가?** 프로젝트 얇은 부트 호스트 `MNSpec` (§7.1) 의 prefab 인스펙터에 spec asset 와이어링 + Resources/Bootstrap/MNSpec.prefab 위치. 어떤 씬에서 Play 시작해도 RuntimeInitializeOnLoadMethod 가 자동 인스턴스화.
6. **EntryPoint 에 spec 코드 박고 있나?** STOP — 인게임 씬 직접 시작 시 안 돌아감. MNSpec.Awake 가 처리. (§7.2)
7. **MNSpec 에 정적 편의 속성 / Get<T> / _cachedSpecDic / InitLocalSpecData 같은 거 두고 있나?** STOP — NSpecData 가 이미 한다. MNSpec 은 인스펙터 spec list 보관 + Awake 부트 트리거 만. (섹션 3.1)
8. **DTO 만들고 있나?** STOP — spec POCO 직접 받기. (섹션 3.2).
9. **NSpecBootstrapSettings 같은 별도 ScriptableObject 자료형 만들고 있나?** STOP — prefab 의 인스펙터 와이어링 + RuntimeInitializeOnLoadMethod 로 처리. (섹션 3.3).
10. **헤드리스에 `using Brainworks.NServer;` 추가하고 있나?** STOP — 빌더는 프로젝트 측 헬퍼에 두기. (섹션 3.4).

---

## 자매 skill

- **`nserver-spec-data`** — 시트 디자인 컨벤션 (시트명, 빈 시트 금지, csv 표현, 첫 행이 타입 결정, 외래키 multi-row 등). 자동 생성 파이프라인이 보는 입력 영역을 다룸.
- **이 skill (`nserver-spec-runtime`)** — 자동 생성된 결과물(`.cs` / `.asset`) 을 런타임 게임 코드에 주입하는 영역.

두 skill 이 다루는 영역은 시트 → 코드 라인을 사이에 두고 정확히 갈라진다. 시트 작업 중에 인게임 코드 wiring 을 묻거든 이 skill, 인게임 wiring 중에 시트 컨벤션이 모호하면 자매 skill 을 참조한다.
