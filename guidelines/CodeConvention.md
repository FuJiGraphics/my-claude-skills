# 코드 컨벤션

Unity / C# 프로젝트의 표준 코드 컨벤션. 코드를 작성하거나 검토할 때 아래 규칙을 따른다. 위반 항목은 보고하고 신규 코드 작성 시 자동 적용한다.

> 관련 문서: [Architecture](./Architecture.md), [Refactoring 스킬](../skills/refactoring/SKILL.md)

## 명명 규칙

| 구분 | 규칙 | 예시 |
|------|------|------|
| Private 필드 | `_` + lowerCamelCase | `_currentHp` |
| Public 필드 | lowerCamelCase | `speed` |
| Public 프로퍼티 | lowerCamelCase | `isDead` |
| const / static | PascalCase | `MaxLevel` |

### UI 컴포넌트 접두사

| 타입 | 접두사 | 예시 |
|------|--------|------|
| RectTransform | `_rt` | `_rtContainer` |
| Image / RawImage | `_img` | `_imgIcon` |
| Button | `_btn` | `_btnConfirm` |
| TextMeshProUGUI | `_txt` | `_txtDesc` |
| TMP_InputField | `_input` | `_inputNickname` |
| Slider | `_sld` | `_sldVolume` |
| Transform | `_tr` | `_trSpawn` |
| Animator | `_anim` | `_animPlayer` |
| ParticleSystem | `_ps` | `_psHitEffect` |
| SkeletonGraphic (Spine) | `_sg` | `_sgCharacter` |
| Coroutine | `_co` | `_coFadeLoop` |
| Sequence (DOTween) | `_seq` | `_seqIntro` |
| DOTweenAnimation | `_tween` | `_tweenFade` |
| bool | `_is` / `_has` / `_can` | `_isDead`, `_hasItem` |
| List / Array | 복수형 명사 | `_items`, `_levels` |
| Dictionary | `Dic` 접미사 | `_itemDic` |
| Index | `Idx` 접미사 | `_currentIdx` |
| Count | `Cnt` 접미사 | `_killCnt` |

### enum 접두사

enum 타입명은 소문자 `e` 접두사 + PascalCase로 작성한다. 값은 PascalCase.

```csharp
public enum ePopupType
{
    PopupSettings,
    PopupShop,
    PopupInventory,
}
```

## 파일 / 클래스 명명

| 접두사 | 의미 | 예시 |
|--------|------|------|
| `MN` | Manager 싱글턴 | `MNGame`, `MNUi`, `MNData` |
| `Cvs` | Canvas UI | `CvsMain`, `CvsLoading` |
| `Popup` | 팝업 UI | `PopupLogin`, `PopupSettings` |
| `Ui` | 비팝업 UI 컴포넌트 | `UiHpBar`, `UiActionSlot` |
| `Cell` | 리스트/그리드 셀 | `CellReward` |

## 매니저 싱글톤 캐싱

`MN<Module>` 매니저(예: `MNUi`, `MNData`, `MNUserData`) 등 글로벌 싱글톤은 **MonoBehaviour 파생 클래스에 한해** `Start` 시점에 1회 캐시 후 사용한다. 매번 `MNXxx.Instance` 호출 회피 + 참조 무결성 검증.

### 규칙 (MonoBehaviour 한정)

- 필드: `private` + `_cachedMgr` 접두사 + 매니저 의미명. 예) `_cachedMgrUi`, `_cachedMgrData`, `_cachedMgrUserData`.
- 캐시 시점: `Start()`. (`Awake`는 다른 객체 Awake 순서 미보장 → 매니저 미초기화 위험)
- 캐시 직후 `AssertHelper.NotNull(typeof(현재클래스), _cachedMgrXxx)`로 검증.
- 이후 멤버 메서드는 `MNXxx.Instance` 대신 `_cachedMgrXxx` 사용.

```csharp
// ✅ MonoBehaviour 클래스
private MNUi _cachedMgrUi;

private void Start()
{
    _cachedMgrUi = MNUi.Instance;
    AssertHelper.NotNull(typeof(PopupSettingsView), _cachedMgrUi);
}

private void OnClickClose()
{
    _cachedMgrUi.ClosePopup(ePopupType.PopupSettings);
}

// ❌ 매번 Instance 호출
private void OnClickClose()
{
    MNUi.Instance.ClosePopup(ePopupType.PopupSettings);
}

// ❌ Awake 캐싱 (다른 컴포넌트 Awake 순서 의존 위험)
private void Awake()
{
    _cachedMgrUi = MNUi.Instance;
}
```

### 예외: Plain 클래스 (Controller, Helper 등 비-MonoBehaviour)

MonoBehaviour의 `Awake` 안에서 `new XxxController(...)` 형태로 즉시 인스턴스화되는 경우가 많다. 이 시점은 다른 매니저들의 `Awake`와 같은 프레임 → 매니저 인스턴스가 아직 준비 안 됐을 위험.

→ **plain 클래스는 캐싱하지 않는다.** 멤버 메서드에서 `MNXxx.Instance`를 직접 호출한다. 호출 시점은 항상 매니저 `Awake` 완료 이후라 NRE 위험 없음.

```csharp
// ✅ Plain 컨트롤러 — 직접 호출, 캐시 안 함
public class PopupSettingsController : BaseController
{
    public void OnClickClose()
    {
        MNUi.Instance.ClosePopup(ePopupType.PopupSettings); // OK
    }
}

// ❌ Plain 컨트롤러에서 ctor 캐싱 — Awake 순서 의존, 잠재적 NRE
public PopupSettingsController(IPopupSettingsView view)
{
    _cachedMgrUi = MNUi.Instance; // 위험
}
```

### 적용 시점

- 신규 `.cs` 작성 시 매니저 사용처 발견 → MonoBehaviour면 캐시 패턴, plain 클래스면 직접 호출.
- `/Refactoring` 실행 시 MonoBehaviour의 `MNXxx.Instance` 직접 호출이 2회 이상이면 캐시 패턴으로 전환. plain 클래스는 변경하지 않는다.
- 단발 호출(`Awake` 1회만 등)은 캐시 불필요.

## UI 책임 분리 (View / Controller)

UI는 MVP 패턴으로 작성한다. View(`BaseView` 계열)와 Controller(`BaseController` 계열)의 경계는 다음과 같다.

| 책임 | View | Controller |
|------|------|-----------|
| 시각 갱신 (`Refresh()`) | ✅ 단일 진입점, abstract 강제 | ❌ Refresh 메서드 두지 않음 |
| 데이터 구독 (`SubscribeData` / `UnsubscribeData`) | ✅ 자기 도메인 `UserData.OnChanged` ± `Refresh` | ❌ |
| 비즈니스 로직 (버튼 클릭 처리, 데이터 변경) | ❌ | ✅ |
| 데이터 조회 (`GetDisplayData()` 등 DTO Getter) | ❌ | ✅ |
| `UserData` mutator 호출 + `RaiseChanged()` | ❌ | ✅ |

### Refresh 흐름

1. UI 매니저가 popup 진입 시점에 `popup.SubscribeData()` → `popup.Refresh()` 호출
2. View의 `Refresh()`는 `_controller.GetDisplayData()`로 DTO를 받아 시각 요소만 갱신
3. 데이터 변경 시점(예: `SomeUserData.RaiseChanged()`)이 발화하면 `SubscribeData`에서 등록된 `Refresh`가 자동 호출

### 단일 위임 금지

`public override void Refresh() => RefreshSomething();` 처럼 1줄 위임은 두지 않는다.
갱신 로직을 `Refresh` 본문에 직접 작성한다 — indirection만 늘어나고 진입점이 둘이 된다.

### Controller 인스턴스 등록 — `SetController` / `GetController<T>`

View는 Awake에서 `SetController<T>(new XxxController(this))`로 인스턴스를 베이스에 등록한다.
`SetController`는 인스턴스를 그대로 반환하므로 `_controller` 캐싱이 한 줄로 끝난다.

```csharp
// ✅ 한 줄
private PopupSettingsController _controller;
private void Awake()
{
    _controller = SetController(new PopupSettingsController(this, _cellOptionView));
}

// ❌ 직접 두 번 대입 (베이스 보유 + 자식 캐시)
_controller = new PopupSettingsController(this, _cellOptionView);
Controller = _controller as BaseController;
```

외부에서 베이스 인스턴스를 다른 타입으로 가져올 일이 있으면 `popup.GetController<XxxController>()`로 조회한다.

### 데이터 구독 시 람다 금지

`SubscribeData` / `UnsubscribeData` 페어는 정확히 같은 메서드 참조를 += / -= 해야 한다.
람다로 등록하면 Unsubscribe 매칭이 실패해 leak 발생. 메서드 참조(`Refresh`)만 사용한다.

```csharp
// ✅
public override void SubscribeData()
{
    var ud = MNUserData.UserData;
    ud.InventoryUserData.OnChanged += Refresh;
}
public override void UnsubscribeData()
{
    var ud = MNUserData.UserData;
    ud.InventoryUserData.OnChanged -= Refresh;
}

// ❌ 람다 — Unsubscribe 매칭 실패로 leak
ud.InventoryUserData.OnChanged += () => Refresh();
```

### `RaiseChanged()` 호출은 데이터 레이어 안에서만

`UserData.RaiseChanged()`는 mutator 메서드 내부에서만 호출한다.
View / Controller에서 외부 호출 금지 (무한루프 방지). Refresh가 데이터 변경을 트리거하면 안 된다.

## 포매팅 규칙

### 가로 정렬 금지

연속된 대입문이나 필드 선언에서 `=`나 타입을 가로로 맞추기 위한 공백 정렬은 사용하지 않는다. 단일 공백 + 자연스러운 들여쓰기만 둔다. 가로 정렬은 한 줄만 추가/수정해도 인접 줄이 모두 변경되어 diff 노이즈를 만든다.

```csharp
// ❌
private int    _currentHp;
private float  _moveSpeed;
private string _name;

// ✅
private int _currentHp;
private float _moveSpeed;
private string _name;
```

### 중괄호 없는 if 본문 뒤 빈 줄

중괄호를 생략한 단문 `if` / `for` / `foreach` 본문 뒤에는 빈 줄을 한 줄 둔다. 본문 범위가 한눈에 끊기게 하기 위함.

```csharp
// ✅
if (target == null)
    return;

DoSomething();

// ❌
if (target == null)
    return;
DoSomething();
```

### `[SerializeField]` 줄 분리

`[SerializeField]` 어트리뷰트는 필드 선언과 같은 줄에 두지 않고 별도 줄에 둔다.

```csharp
// ✅
[SerializeField]
private Image _imgIcon;

// ❌
[SerializeField] private Image _imgIcon;
```

### Doc comment 인라인 금지

`/// <summary>` 블록을 한 줄로 짜지 않는다. 항상 여러 줄로 작성한다.

```csharp
// ❌
/// <summary>적을 처치한다</summary>
public void Kill() { }

// ✅
/// <summary>
/// 적을 처치한다
/// </summary>
public void Kill() { }
```

## 주석

메서드에 `/// <summary>` 사용. 첫 줄: 제목. 둘째 줄(필요 시): 기대 동작·선행 조건. 구현 방식("어떻게")은 쓰지 않는다.
문장이 여러 개인 경우 `.` 마다 줄 바꿈한다.

```csharp
// ✅
/// <summary>
/// 원격 저장소에서 스펙 데이터 다운로드 후 게임 진입
/// </summary>

/// <summary>
/// 크래시 리포터에 유저 연동.
/// 사전에 로그인 필수
/// </summary>

// ❌ 구현 방식 서술 금지
/// <summary>
/// UniTaskCompletionSource를 생성하고 OpenPopup을 호출한 뒤 콜백에서 TrySetResult를 호출한다
/// </summary>
```

단순 getter/setter, 명백한 override는 생략 가능.

## `#region` 표준 순서

클래스 내부 멤버는 [Refactoring 스킬](../skills/refactoring/SKILL.md)에서 정의한 표준 `#region` 순서를 따른다. 신규 클래스 작성 시에도 동일 순서로 작성하고, 기존 클래스 정리는 `/refactoring` 호출로 자동 재배치한다.
