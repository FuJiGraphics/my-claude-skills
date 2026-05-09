---
name: refactoring
description: 지정한 파일의 클래스/모듈 구조를 표준 순서로 재배치하고 접근 제한·주석·포매팅을 정리한다. 로직 변경 없이 구조만 다듬는다. `/refactoring` 호출 시 또는 사용자가 "리팩토링해줘", "이 파일 정리해줘", "구조 좀 다듬어줘"라고 요청할 때 사용한다.
---

# Refactoring

지정한 파일의 구조를 표준 순서에 맞게 정리한다. **로직은 절대 바꾸지 않는다** — 멤버 재배치, 접근 제한 강화, 주석 정리, 포매팅 통일까지가 이 스킬의 영역이다. 결과물은 의미 동등(behavior-equivalent)이어야 하며, 실행 결과·테스트 결과가 변하지 않아야 한다.

로직 수정이 필요해 보이는 부분이 있다면 별도 작업으로 분리하고, 결과 보고 끝에 "후속 작업 후보"로 남긴다.

## 대상 파일 결정

파일이 명시되지 않은 경우 다음 우선순위로 결정한다. 결정 즉시 작업을 시작하며, 사용자에게 다시 묻지 않는다.

1. 사용자가 메시지에서 명시한 파일명
2. 최근 2개 메시지 내 가장 최신 `<ide_opened_file>` 태그
3. 그 외 대화 히스토리의 파일은 무시

## 절차

1. 파일을 읽고 현재 구조와 정리 대상 항목을 짧게 요약 (2~5줄)
2. 멤버를 표준 순서대로 재배치 (아래 "멤버 정렬" 섹션 참조)
3. 외부에서 호출되지 않는 메서드는 더 좁은 접근 제한자(`private`/`protected`)로 강화
4. 주석 처리된 코드(commented-out)는 삭제하거나, 의도가 분명할 경우 `// TODO:` / `# TODO:` 형태로 명시
5. 누락된 doc comment(`/// <summary>`, JSDoc, docstring 등) 추가 — 단순 getter/setter는 제외
6. 포매팅 규칙 적용 (아래 "포매팅 규칙" 섹션 참조)

## 핵심 원칙

- **동작 변경 금지** — 한 줄도 로직을 바꾸지 않는다. 변경의 모든 결과물은 의미 동등이어야 한다. 변경이 의심스러우면 별도 작업으로 분리.
- **변경 폭 최소화** — 같은 효과를 얻을 수 있다면 더 적게 옮긴다. diff가 클수록 리뷰 부담과 머지 충돌 위험이 커진다.
- **이름·시그니처 변경 금지** — 식별자 정리는 별도 작업. 호출부에 영향을 주는 변경은 이 스킬의 범위 밖.

## 멤버 정렬

OO 언어 전반에 통용되는 그룹 순서:

```
Fields → Properties / Accessors → Events → Lifecycle Callbacks → Public Methods → Private/Protected Methods → Nested Types
```

| 그룹 | 포함 대상 |
|------|----------|
| Fields | 상수 → static → 직렬화/주입 필드(예: `[SerializeField]`, `@Inject`) → protected → private |
| Properties / Accessors | 모든 프로퍼티·접근자 (override 포함). 단순 getter는 expression-bodied 형식 |
| Events | 이벤트, 콜백 필드 (`Action`, `event`, `EventEmitter` 등) |
| Lifecycle Callbacks | 프레임워크 라이프사이클 (Unity의 `Awake`/`Start`/`Update`, React의 `componentDidMount`, Android의 `onCreate` 등). 호출 순서대로 정렬 |
| Public Methods | 외부에서 호출 가능한 모든 메서드 |
| Private/Protected Methods | 내부 구현 메서드, 이벤트 핸들러(`On*` 접두사), 코루틴/async helper |
| Nested Types | 내부 enum, struct, class |

그룹 내에서는 자연스러운 가독성 순서(생성 → 변환 → 조회 등)를 유지한다.

## 포매팅 규칙 (언어 공통)

### 가로 정렬 금지

`=`, `:`, `return` 등의 위치를 세로로 맞추기 위해 공백을 패딩하지 않는다. 한 줄을 추가·수정할 때마다 정렬을 다시 맞춰야 하므로 diff가 누적되고 머지 충돌도 늘어난다.

```csharp
// ❌ 공백 패딩으로 가로 정렬
var userName    = user.Name;
var cacheKey    = PrefsKey(user);
int appVersion  = ParseVersion(...);

// ✅ 정렬 없이 그대로 작성
var userName = user.Name;
var cacheKey = PrefsKey(user);
int appVersion = ParseVersion(...);
```

같은 규칙이 `return` 문, 객체 리터럴 키 정렬에도 동일하게 적용된다.

### 중괄호 없는 제어문 뒤 빈 줄 1개

`if`/`for`/`while` 본문을 중괄호 없이 다음 줄에 쓸 경우, 블록 이후 **빈 줄 1개**를 추가해 다음 코드와 시각적으로 분리한다. `continue`, `break`, `return`, `throw` 등 제어 흐름 문장 모두 동일하게 적용한다. 빈 줄이 없으면 어디까지가 분기 본문인지 한눈에 들어오지 않는다.

```csharp
// ❌ 구분 없음
if (result == null)
    continue;
DoSomething();

if (index < 0)
    break;
Process(index);

// ✅ 빈 줄로 구분
if (result == null)
    continue;

DoSomething();

if (index < 0)
    break;

Process(index);
```

`if (cond) return ...;`처럼 본문과 조건이 한 줄에 들어가는 인라인 형태는 그대로 두어도 된다. 단, 가로 정렬을 위해 패딩하지는 않는다.

### Doc comment 스타일

doc comment는 인라인 한 줄(`/// <summary> 설명 </summary>`)로 쓰지 않고 항상 줄바꿈한 블록 형태로 쓴다. 인라인은 설명이 길어질 때 한꺼번에 깨지고, 줄 단위 diff가 깔끔하게 잡히지 않는다.

```csharp
// ❌ 인라인
/// <summary> 오토 모드 활성화 여부 </summary>
public bool IsAuto;

// ✅ 줄바꿈 블록
/// <summary>
/// 오토 모드 활성화 여부
/// </summary>
public bool IsAuto;

// ✅ 보충 설명이 필요한 경우 — 구분자 사용 가능
/// <summary>
/// 현재 남은 HP.
/// 0이 되면 사망 처리
/// </summary>
public int Hp;
```

같은 정신(인라인 docstring 회피, 여러 줄 블록 선호)이 다른 언어의 doc comment에도 적용된다 — JSDoc(`/** */`), Python docstring(`"""..."""`), Rust(`///`), Java(`/** */`).

## 옵션: C# / .NET — `#region` 정렬

C# 파일에서는 `#region`을 사용해 위 "멤버 정렬"의 그룹을 명시적으로 묶을 수 있다. 7개 표준 region명만 사용한다.

```
#region Fields
#region Properties
#region Events
#region Unity Methods            // Unity 프로젝트인 경우만 사용
#region Public Methods
#region Private Methods
#region Nested Types
```

Unity가 아닌 .NET 프로젝트라면 `Unity Methods`를 `Lifecycle` 또는 해당 프레임워크의 라이프사이클명으로 대체하거나, 라이프사이클 콜백이 없으면 생략한다.

예외: protected 메서드가 많으면 `#region Protected Methods`를 별도로 둘 수 있다.

### `#region` 포매팅

```csharp
#region Fields

    public static int Count;
    private bool _isInitialized;

#endregion
#region Properties

    public int Level => _level;

#endregion
```

- `#region` / `#endregion`은 들여쓰기 없이 컬럼 0
- `#region` 직후, `#endregion` 직전에 빈 줄 1개
- `#endregion`과 다음 `#region` 사이에는 빈 줄 없이 바로 붙임
- region 이름은 위 표준명만 사용 (기능명·한글·자유 텍스트 금지) — 표준명을 강제해야 파일 간 구조가 일관되고 IDE 폴딩 결과도 예측 가능해진다

### C#이 아닌 언어에서

`#region` 디렉티브 자체는 C#/.NET에 한정된다. 다른 언어에서는 region 마커를 쓰지 않고 빈 줄 + 짧은 주석 헤더(`// --- Public API ---` 등)로만 그룹을 분리하거나, 그룹 사이에 빈 줄 2개를 두어 시각적으로 구분한다. 그룹 순서 자체는 위 "멤버 정렬"을 따른다.

## 옵션: Unity / MonoBehaviour 추가 규칙

Unity 프로젝트에서만 적용된다. Unity가 아닌 코드라면 이 절은 건너뛴다.

### `[SerializeField]` 포맷

`[SerializeField]` 어트리뷰트와 필드 선언을 **반드시 줄 분리**한다. `private` 한정자는 필드 선언 줄에만 쓴다. 어트리뷰트가 여러 개일 때 추적이 쉬워지고, 필드명 grep도 깔끔해진다.

```csharp
// ❌
[SerializeField] private Button _btnConfirm;

// ✅
[SerializeField, Required]
private Button _btnConfirm;
```

### Null 검증 — UI MonoBehaviour 한정

UI 계층의 MonoBehaviour 자식(View 베이스 / Controller 베이스 자식 등)에서 `[SerializeField]`로 선언한 참조 필드는 `Awake`에서 null 검사를 수행한다. 인스펙터에서 참조가 빠진 채 빌드에 들어가면 런타임 NRE로 이어지므로, 빠르게 실패시키기 위해서다.

```csharp
private void Awake()
{
    AssertHelper.NotNull(typeof(MyClass), _btnConfirm);
    AssertHelper.NotNull(typeof(MyClass), _txtLabel);
}
```

UI 외 영역(인게임 로직, 매니저, 스킬 등)의 MonoBehaviour는 적용 대상이 아니다 — 인스펙터로 참조를 잡지 않는 코드까지 강제하면 노이즈가 된다.

`AssertHelper` 같은 프로젝트 헬퍼가 없다면 동일한 의도로 `Debug.Assert(_btnConfirm != null)` 또는 직접 `if (x == null) throw ...`로 대체한다.

### 매니저 싱글톤 캐싱

프로젝트의 매니저 싱글톤(예: `XxxManager.Instance`)을 한 클래스에서 **2회 이상** 호출한다면 `Start()`에서 캐시 + null 검증 패턴으로 전환한다 — **단, MonoBehaviour 한정**.

Plain 클래스(Controller, Helper 등)는 ctor 캐싱 시 다른 매니저의 `Awake` 순서에 의존하게 되어 NRE 위험이 생긴다. 이 경우 캐시하지 않고 `XxxManager.Instance`를 호출 지점에서 직접 참조하는 쪽이 안전하다.

### View / Controller 책임 분리

프로젝트가 UI를 View / Controller로 나눠 관리한다면 다음 위반이 보일 때 정리한다 (베이스 클래스명은 프로젝트마다 다르므로 역할로 식별):

- **Controller에 `Refresh` / `SubscribeData` / `UnsubscribeData`가 있으면 View로 이관 후 Controller에서 제거.** Controller에는 비즈니스 로직과 DTO Getter(`GetDisplayData()` 등)만 남긴다.
- **View의 `Refresh`가 1줄 위임이면 위임 대상의 본문을 `Refresh`로 흡수.** `public override void Refresh() => RefreshList();` 형태가 보이면 `RefreshList()` 본문을 `Refresh()`로 옮기고 호출처를 정리 — 진입점만 분리한 indirection은 가치가 없다.
- **View의 Awake에서 컨트롤러 등록이 두 줄(`_controller = new XxxController(...)` + `Controller = _controller as BaseController;`)로 보이면 한 줄로 통합** — 베이스에 통합 헬퍼(`SetController` 등)가 있다면 그쪽으로.
- **Subscribe/Unsubscribe에 람다가 있으면 메서드 참조로 교체.** 람다는 `-=` 매칭 실패로 leak이 발생한다.
- **데이터 변경 이벤트 발행(`UserData.RaiseChanged()` 등)이 View / Controller에 있으면 데이터 mutator 메서드 안으로 이동.** 시각 갱신 코드에서 데이터 이벤트를 발행하면 무한루프 위험.

## 결과물 형식

리팩토링 작업이 끝나면 다음 형식으로 결과를 보고한다:

1. **변경 요약** — 어떤 그룹으로 재배치했는지, 접근 제한을 강화한 메서드, 정리한 주석 등 (3~6줄)
2. **변경 파일 경로** — 수정한 파일 (1개여야 정상)
3. **후속 작업 후보** — 로직 변경이 필요해 보이는 항목이 있다면 따로 나열 (이 스킬의 범위 밖이므로 적용하지 않음)
