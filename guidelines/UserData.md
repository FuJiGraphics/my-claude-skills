# 유저 데이터 시스템 (클라우드 영속화 + 로컬 직렬화 패턴)

모바일 게임에서 **인벤토리 / 진행도 / 통화 / 장비 같은 유저별 영속 데이터**를 다루는 일반 패턴 참조 문서. 한 프로젝트의 구체 백엔드 사양이 아니라 **서버 권위 데이터 → 로컬 메모리 표현 → mutator 경유 변경 → 이벤트 발행 → View 구독** 흐름 자체를 다룬다.

> 어떤 클라우드 DB·직렬화 포맷·이벤트 디스패처를 고를지는 프로젝트마다 자유. 본 문서는 **선택지를 묶어 보여주는 레퍼런스**다. 결정한 조합은 프로젝트의 `CLAUDE.md` 또는 별도 UserData 문서에 명시한다.

---

## 핵심 파이프라인

```
[클라우드 DB]                    (서버 = 권위, Single Source of Truth)
        │
        ▼  ── 클라이언트 부팅 시 fetch
        │
[로컬 메모리 객체]               (UserData 루트 + 도메인별 서브 객체)
        │
        ▼  ── mutator 메서드만 수정 가능
        │
[변경 이벤트 발행]               (mutator 내부에서 RaiseChanged)
        │
        ▼
[View / Controller 구독]         (UI는 이벤트로만 갱신)
```

각 단계의 흔한 선택지:

| 단계 | 선택지 (예시) |
|------|-----------|
| 클라우드 DB | Firebase Firestore, Firebase Realtime DB, Supabase, AWS DynamoDB, 사내 REST 백엔드 |
| 인증/UID | OAuth 토큰, Firebase Auth UID, 게스트 디바이스 UUID, 사내 계정 시스템 |
| 직렬화 포맷 | JSON, MessagePack, Protobuf |
| 변경 이벤트 | C# `event` / Action, MessagePipe, UniRx, 커스텀 EventBus |
| 충돌 감지 | 서버 타임스탬프 + 로컬 비교, 버전 카운터, OT/CRDT |

---

## 권위(authority) 모델

유저 데이터는 **항상 서버가 권위 소스**다. 클라이언트는 캐시일 뿐.

| 원칙 | 설명 |
|------|------|
| 서버 권위 | 분쟁 시 항상 서버 값을 신뢰. 클라 로컬 상태는 즉시 덮어쓰기 가능 |
| 단일 진입점 | `UserDataManager`(또는 `MN<Module>`)가 fetch/save/접근의 유일한 경로 |
| Mutator 경유 | 외부에서는 필드 직접 수정 금지, mutator 메서드만 사용 |
| 이벤트 발행 위치 | mutator **안**에서만 `RaiseChanged()` 호출 — View/Controller에서는 호출 금지 |

이 분리 원칙이 깨지면 "UI는 갱신됐는데 데이터는 안 바뀜" / "데이터는 바뀌었는데 UI가 따라오지 않음" 류 버그가 나온다.

---

## UserData 계층 (예시)

루트 `UserData` 1개 + 도메인별 서브 데이터로 분할한다. 단일 문서/단일 객체로 다루기 위해 평탄화 대신 **도메인 단위 서브 객체**를 권장.

```
UserData (루트)
├── UserInfoUserData       — UUID, 마지막 저장 시각, 클라 버전
├── InventoryUserData      — 통화/재료 (Dictionary<string, ItemEntry>)
├── EquipUserData          — 장비 인벤/장착/강화 (List + Dictionary 혼합)
├── ProgressUserData       — 스테이지 진행도, 클리어 기록
├── CollectionUserData     — 도감/유물/수집 보상 (Dictionary 기반)
└── CraftUserData          — 제작 큐 (List<CraftEntry>)
```

도메인 분리 기준:

- **시트 한 장으로 떨어지는 영역**(인벤토리·장비)은 한 서브로
- **변경 빈도/리스너 범위가 다른 영역**은 분리(예: 통화는 자주 변함, 도감은 간헐적)
- **세이브 단위 분리가 필요한 영역**(우편함·랭킹 등 서버 푸시 채널)은 별도

---

## 직렬화 패턴

직렬화 포맷은 한 가지를 선택해 일관 적용한다. 아래 예시는 JSON 기반 + 클라우드 DB의 어트리뷰트 매핑 + Unity Odin 직렬화를 함께 쓰는 케이스. 다른 포맷(Protobuf 등)을 쓰는 경우 어트리뷰트만 바뀐다.

```csharp
[CloudSerializable]              // 클라우드 DB 직렬화 마킹 (예: [FirestoreData])
[Serializable]                   // Unity 직렬화
public class InventoryUserData
{
    [OdinSerialize][CloudProperty]
    public int Field { get; set; }

    [OdinSerialize][CloudProperty]
    public Dictionary<string, ItemEntry> Items { get; set; } = new();

    [NonSerialized]              // 런타임 전용 캐시는 직렬화 제외
    private Dictionary<int, ItemEntry> _runtimeIndex;
}
```

### 컨벤션

| 항목 | 규칙 |
|------|------|
| Dictionary key | 항상 `string` (대부분의 클라우드 DB 제약) — enum을 키로 쓰면 `.ToString()` 변환 |
| 기본값 | 컬렉션 필드는 `= new()` 초기화 필수 (역직렬화 시 null 방지) |
| 새 필드 추가 | 어트리뷰트만 붙이면 자동 직렬화/역직렬화되도록 매니페스트형 등록을 피한다 |
| 런타임 전용 | `[NonSerialized]` 또는 동등 마킹으로 명시 |
| 시각/타임스탬프 | 서버 타임스탬프(서버가 박는 값)와 로컬 시각을 분리 저장 |

---

## 저장/로드 흐름

```
저장: SaveLoadManager.SaveData() → UserDataManager.SaveUserData() [Fire-and-forget]
로드: SaveLoadManager.LoadData() → UserDataManager.LoadUserData() [Fire-and-forget]
```

- 저장 직전 `LastWriteAt = ServerTimestamp` 자동 설정 (서버가 박는 값)
- mutator 호출부(또는 컨트롤러)는 **데이터 변경 후** `SaveLoadManager.Instance.SaveData()`를 한 번 호출
- 짧은 시간 내 다중 변경이 일어나면 **debounce**(예: 1프레임 또는 N초 그룹) 권장 — 매 변경마다 네트워크 요청 X
- 초기화 시퀀스 예시: `SessionManager` → `LoadUserDataAsync()` → 도메인 리스너 시작 → 첫 화면 진입

---

## 실시간 동기화 (리스너)

서버 측 변경(다른 디바이스, 운영자 보정, 우편 푸시 등)을 클라이언트가 인지해야 하는 경우 **리스너**를 둔다.

| 리스너 (예시) | 대상 | 역할 |
|--------------|------|------|
| UserDocListener | `users/{uuid}` | 서버 강제 변경 감지 → 충돌 시 재접속 요구 |
| TriggerListener | `trigger/...` | 서버 셧다운/긴급 공지 신호 |
| MailSignalListener | `signals/mail` | 우편 업데이트 신호 |

### 충돌 감지

- 로컬과 서버 데이터를 **JSON 비교** 또는 **버전 카운터**로 충돌 판정
- DB가 제공하는 메타(예: `metadata.HasPendingWrites`)로 "내가 막 쓴 변경의 에코"인지 구분
- 충돌 발생 시 정책:
  - **재접속 강제** — 단일 세션 가정 게임에서 가장 안전
  - **서버 우선 머지** — 도감/통계 같은 단조 증가 영역
  - **사용자 선택** — 진행도 같은 비단조 영역(흔치 않음)

### 오프라인 / 롤백

- 일시적 네트워크 단절 동안은 로컬 메모리에 변경을 누적하고, 복구 시 일괄 저장
- 저장 실패가 일정 횟수 누적되면 **마지막 서버 스냅샷으로 롤백** + 사용자 안내
- 클라이언트가 서버를 못 따라잡는 경우(예: 클라 버전이 너무 오래됨)는 **업데이트 강제 화면**으로 분기

---

## Mutator 패턴 (변경 이벤트 발행 지점)

데이터 수정의 모든 경로를 mutator로 모은다. mutator의 책임:

1. 입력 검증 (음수 차감 방지 등)
2. 로컬 메모리 갱신
3. 변경 이벤트 발행 (`RaiseChanged()` 또는 동등)
4. 저장 트리거(필요 시)

```csharp
public class InventoryUserData
{
    public event Action<string, int> OnCurrencyChanged;

    public void AddCurrency(string key, int delta)
    {
        if (!Items.TryGetValue(key, out var entry))
            entry = new ItemEntry();

        entry.Count += delta;
        if (entry.Count < 0) entry.Count = 0;

        Items[key] = entry;
        OnCurrencyChanged?.Invoke(key, entry.Count);   // mutator 안에서만 발행
    }
}
```

### 카테고리 분기형 진입점

루트 `UserData`에 카테고리 자동 분기 메서드를 두면 보상 처리 코드가 깔끔해진다.

```csharp
public void AddItem(int itemId, int cnt)
{
    var category = SpecManager.Item.GetCategory(itemId);
    switch (category)
    {
        case Category.Currency:  Inventory.AddCurrency(itemId, cnt); break;
        case Category.Mat:       Inventory.AddMat(itemId, cnt); break;
        case Category.Equip:     Equip.CreateAndAdd(itemId, cnt); break;
        case Category.Collection: Collection.AddPieces(itemId, cnt); break;
        // 새 도메인이 들어오면 여기에 분기 추가
    }
}
```

---

## View / Controller 책임 분리

| 레이어 | 허용 | 금지 |
|--------|------|------|
| Mutator (UserData 내부) | 메모리 수정, 이벤트 발행, 저장 트리거 | — |
| Controller / Manager | mutator 호출, 시퀀스 조립 | 필드 직접 수정, 이벤트 직접 발행 |
| View (`BaseView` 등) | 이벤트 구독, 표시 갱신 | mutator 우회, 이벤트 직접 발행, 필드 수정 |

```csharp
public class InventoryView : BaseView
{
    public override void OnOpen()
    {
        UserDataManager.Inventory.OnCurrencyChanged += HandleCurrencyChanged;
        Refresh();
    }

    public override void OnClose()
    {
        UserDataManager.Inventory.OnCurrencyChanged -= HandleCurrencyChanged;
    }

    private void HandleCurrencyChanged(string key, int newCount) => Refresh();
}
```

> **중요**: View가 직접 `RaiseChanged()`를 호출하면 "UI 깜빡임 → 데이터 미반영" 패턴이 발생한다. 발행 권한은 mutator만.

---

## 컬렉션 선택 기준

| 패턴 | 사용처 | 선택 이유 |
|------|--------|----------|
| `Dictionary<string, T>` | 통화, 도감, 수집형 | 키 기반 빠른 조회, 추가/삭제 빈번 |
| `List<T>` | 제작 큐, 순차 보상 큐 | 순차 처리/열거 / 순서가 의미 있음 |
| List + Dictionary 혼합 | 장비 인벤+장착 | 인벤(List 순회) + 장착(슬롯별 Dict 조회) |

---

## 새 서브 데이터 추가 절차 (체크리스트)

새 도메인(예: `Quest`, `Pet`, `Daily`...)을 유저 데이터에 추가할 때의 순서.

### 1단계 · 클래스 정의

| 작업 | 설명 |
|------|------|
| 서브 클래스 생성 | `[CloudSerializable][Serializable] class XxxUserData` |
| 필드 어트리뷰트 | 각 필드에 `[OdinSerialize][CloudProperty]` (또는 동등) |
| 컬렉션 기본값 | `= new()` 초기화 — 역직렬화 시 null 방지 |
| 런타임 전용 | `[NonSerialized]` 마킹 |

### 2단계 · 직렬화 등록

| 작업 | 설명 |
|------|------|
| 자동 직렬화 확인 | 어트리뷰트 기반이라면 별도 매니페스트 등록 불필요 |
| 명시 등록형이라면 | 직렬화 매니페스트(예: `KnownTypes`)에 추가 |
| 마이그레이션 | 기존 유저 문서에 새 필드가 없을 때 기본값으로 채워지는지 확인 |

### 3단계 · 매니저 통합

| 작업 | 설명 |
|------|------|
| 루트 `UserData` 추가 | 같은 어트리뷰트로 프로퍼티 추가, `= new()` 기본값 |
| `UserDataManager` 접근자 | `UserDataManager.Quest` 같은 정적 접근자 노출 |
| `AddItem` 분기 | 보상으로 들어올 수 있는 도메인이면 카테고리 분기 추가 |

### 4단계 · 변경 이벤트 발행 지점 정의

| 작업 | 설명 |
|------|------|
| 이벤트 정의 | `event Action<...> OnXxxChanged` (필요 단위로 분할) |
| Mutator 작성 | 외부에서 호출할 모든 변경 경로를 mutator로 묶기 |
| 발행 위치 | mutator 안에서만 `?.Invoke(...)` |
| 저장 트리거 | mutator 끝에서(또는 컨트롤러 한 곳에서) `SaveData()` |

### 5단계 · View 구독

| 작업 | 설명 |
|------|------|
| `OnOpen` 구독 | 이벤트 핸들러 부착 + 즉시 `Refresh()` |
| `OnClose` 해제 | 누수 방지를 위해 반드시 해제 |
| 필드 직접 참조 금지 | View는 mutator 우회 X — 표시만 |

---

## 관련 파일 (일반 컨벤션)

> 실제 루트 폴더명은 프로젝트별로 정한다. 중요한 것은 **역할별 분리**.

| 파일 | 역할 |
|------|------|
| `Assets/Scripts/UserData/UserData.cs` | 루트 유저 데이터 + `AddItem` 카테고리 분기 |
| `Assets/Scripts/UserData/<Domain>UserData.cs` | 도메인별 서브 데이터 + mutator + 이벤트 |
| `Assets/Scripts/Managers/UserDataManager.cs` | fetch/save 진입점, 정적 접근자 |
| `Assets/Scripts/Managers/SaveLoadManager.cs` | 저장 debounce, 큐잉, 실패 재시도 |
| `Assets/Scripts/Server/<DB>.cs` | 클라우드 DB 어댑터 (Firestore/Supabase/REST 등) |
| `Assets/Data/UserData/` | 로컬 임시 캐시 / 마이그레이션 스크립트 |

---

## 운영 시 주의

- **마이그레이션 누락**: 기존 유저 문서에 신규 필드가 없을 때 기본값으로 채워지지 않으면 부팅 시 NRE. 새 컬렉션 필드는 반드시 `= new()` 또는 역직렬화 후 보정 단계
- **이벤트 누수**: View `OnClose`에서 핸들러 해제 누락 시 닫힌 팝업이 살아 있는 것처럼 동작. 베이스 클래스에서 자동 해제 패턴을 두면 안전
- **다중 디바이스**: 같은 계정으로 두 디바이스가 동시에 진입하면 마지막-쓰기-승리(last-writer-wins)가 된다. 단일 세션을 강제하려면 리스너로 강제 로그아웃 처리
- **저장 폭주**: mutator마다 즉시 저장하면 네트워크 비용/요금 폭증. debounce 또는 의미 단위(전투 종료, 화면 전환)로 묶기
- **개발 빌드 ↔ 라이브 빌드 분리**: 같은 클라이언트가 환경에 따라 다른 DB 인스턴스를 보도록 설정 — 운영 데이터 오염 방지
- **롤백 가능한 구조**: 서버 스냅샷을 주기적으로 백업해두면 사고 시 복구 가능. 클라 단독 자동 롤백은 데이터 손실 위험이 크므로 신중히
