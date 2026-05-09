# 스펙 데이터 파이프라인 (원격 + 로컬 캐시 패턴)

모바일 게임에서 **밸런싱 수치 / 캐릭터·아이템 스탯 / 스테이지 정의** 등 "스펙 데이터"를 다루는 일반 패턴 참조 문서. 한 프로젝트의 구체 스택이 아니라 **원격 소스 → 버전 체크 → 로컬 캐시 → 메모리 표현** 흐름 자체를 다룬다.

> 어떤 스토리지·포맷·런타임 표현을 고를지는 프로젝트마다 자유. 본 문서는 **선택지를 묶어 보여주는 레퍼런스**다. 결정한 조합은 프로젝트의 `CLAUDE.md` 또는 별도 SpecData 문서에 명시한다.

---

## 핵심 파이프라인

```
[원본 데이터 소스]               (기획자/디자이너 편집 영역)
        │
        ▼
[빌드/변환 단계]                 (검증 + 직렬화 포맷 변환)
        │
        ▼
[원격 저장소]                    (버전 태그 + 파일 호스팅)
        │
        ▼  ── 클라이언트가 버전 체크 후 다운로드
        │
[로컬 캐시]                      (오프라인/재실행 대비)
        │
        ▼
[메모리 표현]                    (런타임 조회용 자료구조)
```

각 단계의 흔한 선택지:

| 단계 | 선택지 (예시) |
|------|-----------|
| 원본 데이터 소스 | 구글 시트, Excel, Notion DB, 사내 CMS |
| 빌드/변환 | CI 스크립트, 사내 콘솔 툴, 에디터 메뉴 |
| 직렬화 포맷 | JSON, CSV, MessagePack, Protobuf, FlatBuffers |
| 원격 저장소 | Firebase Storage, AWS S3, 사내 CDN, GitHub Release |
| 로컬 캐시 | PlayerPrefs, persistentDataPath 파일, SQLite |
| 메모리 표현 | Unity의 경우 ScriptableObject가 자연스러운 선택 / 일반 dict / record |

---

## 버전 관리

스펙 데이터의 핵심 운영 이슈는 **언제·어떻게 클라이언트가 새 버전을 받는가**이다.

### 1) 파일명·메타에 버전 박기

원격 저장소의 파일명 또는 메타 파일에 버전을 포함시키는 패턴.

- 파일명 패턴 예: `{SpecName}_{version}.{ext}` (예: `Character_12.json`)
- 또는 별도 매니페스트 파일: `manifest.json` 안에 `{ "Character": 12, "Item": 7 }`
- 클라이언트는 **현재 캐시된 버전**과 **원격 매니페스트의 버전**을 비교

### 2) 업데이트 정책

| 정책 | 설명 | 어울리는 데이터 |
|------|------|-----------------|
| 강제 업데이트 (Blocking) | 앱 진입 직전 매니페스트 비교 → 다르면 다운로드 완료 후에만 진행 | 전투 밸런스, 매치 가능 여부 |
| 백그라운드 업데이트 | 캐시본으로 일단 진입 → 백그라운드에서 받아 다음 부팅에 적용 | 도감, 튜토리얼 텍스트 |
| 이중화 | 일부 스펙은 강제, 일부는 백그라운드 | 대부분의 운영 게임 |

### 3) 캐시 무결성

- 다운로드 완료 후에만 캐시 파일을 교체(임시 파일에 저장 → rename)
- 체크섬(CRC32 / SHA-1) 검증 권장
- 캐시 손상 시 폴백: 앱에 번들된 초기 스펙 데이터로 부트, 다시 다운로드 시도

---

## 메모리 표현

### Unity: ScriptableObject 컨테이너 패턴

Unity 환경에선 스펙 한 종류당 ScriptableObject 컨테이너 1개 + 내부 리스트 + 빠른 조회용 dict 구성이 자연스럽다.

```csharp
public class XxxSpecScriptableData : SpecScriptableData
{
    public List<XxxSpecData> _list;
    private Dictionary<TKey, XxxSpecData> _dict;

    public override void Init()
    {
        base.Init();
        _dict = new Dictionary<TKey, XxxSpecData>();
        foreach (var data in _list)
            _dict[data.key] = data;
    }

    public XxxSpecData GetXxxSpecData(TKey key)
        => _dict.TryGetValue(key, out var data) ? data : null;
}
```

베이스 클래스(예: `SpecScriptableData`)가 담당할 역할:

- `PopulateFromJson(string json)` — 원격에서 받은 직렬화 문자열을 `_list`로 채움
- `SerializeToJArray()` — 디버그/덤프용 역직렬화
- `Init()` — dict/룩업 캐시 구축

### 매니저: `SpecManager` (또는 `MN<Module>`)

스펙 컨테이너들을 모아 관리하는 싱글톤. 정적 프로퍼티로 노출하면 호출부가 깔끔하다.

```csharp
public static XxxSpecScriptableData Xxx => Get<XxxSpecScriptableData>();
```

매니저의 책임:

- 부팅 시 매니페스트 비교 → 필요한 스펙 다운로드
- 다운로드된 데이터를 컨테이너에 주입(`PopulateFromJson` → `Init`)
- 호출부가 단일 진입점(`SpecManager.Character`)으로 접근하도록 노출

### 비-Unity / 일반 환경

Unity가 아닌 환경에서는 ScriptableObject 대신 `Dictionary<TKey, TSpec>`을 직접 들고 있는 일반 클래스로 충분하다. **핵심은 "한 종류의 스펙당 한 컨테이너 + 키 기반 즉시 조회"**라는 모양이다.

---

## 공통(Item) 테이블로 중복 컬럼 흡수하기

여러 스펙이 공유하는 속성(예: 등급, 아이콘, 카테고리)은 **공통 테이블 한 곳에서 관리**하고, 개별 스펙은 ID로 참조한다.

- 개별 스펙 테이블에 `grade`/`iconPath`/`category` 같은 컬럼을 직접 두지 않는다
- 공통 `Item` 테이블에 `itemId`, `key`, `grade`, `category`, ... 등을 두고
- 개별 스펙은 동일한 `itemId`를 외래키처럼 사용

```csharp
// 등급이 필요할 때 — 공통 테이블 참조
var grade = SpecManager.Item?.GetItemSpecData(characterId)?.grade;
```

장점:

- 등급 체계 변경 시 한 곳만 손보면 됨
- 신규 스펙이 같은 도메인에 들어와도 자동으로 공통 속성 흡수
- 아이콘 경로 같은 리소스 컨벤션을 한 곳에서 강제 가능

---

## 새 스펙 추가 절차 (체크리스트)

새로운 도메인(예: `Character`, `Item`, `Stage`, `Quest`...)을 추가할 때 일반적인 작업 순서. **기획자(데이터)** + **개발자(코드/등록)** 가 같이 움직인다.

### 1단계 · 데이터 정의 (기획자 + 개발자)

| 작업 | 설명 |
|------|------|
| 공통 Item 테이블 행 추가 | `itemId`, `key`, `grade`, `category` 같은 공통 속성 등록 |
| 전용 시트/테이블 생성 | 해당 도메인 고유 컬럼 정의 (예: Character → `hp`, `atk`, `moveSpeed`) |
| ID 정합성 | 전용 시트의 ID가 공통 Item 테이블 `itemId`와 동일해야 참조 연결됨 |

### 2단계 · 코드 등록 (개발자)

| 영역 | 작업 |
|------|------|
| Enum / 상수 | 새 카테고리·아이템 enum 추가 (번호 대역 할당) |
| 공통 아이콘 로더 | 카테고리별 아이콘 경로 분기 추가 |
| 빌드 도구 등록 | 스펙 자동 생성 도구의 대상 목록(`SpecNames` 등)에 새 이름 추가 |
| 매니저 프로퍼티 | `SpecManager`에 정적 접근자 추가 |
| 컨테이너 헬퍼 | 자동 생성된 `XxxSpecScriptableData`에 `Init()` override + `GetXxx()` 같은 헬퍼 |
| 인스펙터/등록 | (Unity의 경우) 매니저 인스펙터의 컨테이너 리스트에 `.asset` 등록 |

### 3단계 · 자동 생성 vs 수동 작성

- 스펙 데이터 클래스(`XxxSpecScriptableData.cs`)와 로컬 번들 파일(JSON 등)은 **빌드 도구로 자동 생성**되는 것이 일반적
- 자동 생성 산출물은 **직접 편집 금지** (다음 빌드에서 덮어씀)
- 헬퍼 메서드처럼 사람이 추가하는 부분은 partial class 또는 별도 파일로 분리

---

## ID 번호 대역 컨벤션 (예시)

대역을 미리 갈라두면 디버깅·시트 작업 시 도메인 식별이 쉬워진다. 아래는 한 가지 예시일 뿐이며, 프로젝트마다 자유롭게 잡으면 된다.

| 대역 | 용도 |
|------|------|
| 1~9 | 기본 화폐 |
| 1100~2010 | 장비 |
| 10001~16010 | 재료 |
| 20000~20009 | (도메인 A) |
| 30000~30005 | (도메인 B) |

---

## 아이콘 / 리소스 경로 컨벤션 (예시)

공통 Item 테이블의 `category` 값에 따라 아이콘 경로 규칙을 분기시키면, 신규 카테고리 추가 시 변경 지점이 한 곳에 모인다.

| category | 경로 패턴 |
|----------|-----------|
| Equip | `Assets/Res/UI/Icon/EquipIcon/{itemId}.png` |
| Currency | `Assets/Res/UI/Icon/CurrencyIcon/{key}.png` |
| Mat | `Assets/Res/UI/Icon/MatIcon/{key}.png` |
| (도메인 A) | `Assets/Res/UI/Icon/(도메인A)Icon/{itemId}.png` |
| (도메인 B) | `Assets/Res/UI/Icon/(도메인B)Icon/{itemId}.png` |

> 실제 루트 폴더명(`Assets/Res` vs `Assets/A_Res` 등)은 프로젝트 컨벤션을 따른다.

---

## 직렬화 컨벤션

- **JSON 필드명**: `camelCase` (예: `itemType`, `boxKey`, `maxHp`)
- 직렬화 포맷이 CSV라면 **헤더명**을 동일 컨벤션으로 통일
- 시트 컬럼명 ↔ 필드명 사이 변환 규칙을 빌드 도구가 강제

---

## 관련 파일 (일반 컨벤션)

> 실제 루트 폴더명은 프로젝트별로 정한다. 중요한 것은 **역할별 분리**.

| 파일 | 역할 |
|------|------|
| `Assets/Scripts/Data/SpecScriptableData.cs` | 베이스 클래스 — `PopulateFromJson()`, `SerializeToJArray()`, `Init()` |
| `Assets/Scripts/Managers/SpecManager.cs` | 스펙 캐시 관리, 정적 접근자 (`Get<T>()`) |
| `Assets/Scripts/Editor/<DevTool>.cs` | 스펙 캐시 상태 시각화, 빌드 도구의 `SpecNames` 배열 |
| `Assets/Data/Spec/` | 로컬 번들 파일 + ScriptableObject `.asset` |
| `Assets/Data/Spec/ItemSpecScriptableData.cs` | 공통 아이템 스펙 — grade, 아이콘 로드, 카테고리 분기 |

---

## 운영 시 주의

- **버전 충돌**: 클라이언트 빌드와 원격 스펙 버전이 호환되지 않을 수 있다. 매니페스트에 `minClientVersion`을 같이 두면 안전
- **다운로드 실패**: 네트워크 오류 시 캐시본으로 폴백 + 사용자에게 재시도 옵션 제공
- **점진적 롤아웃**: 모든 유저에게 한 번에 새 스펙을 푸시하는 대신, A/B 또는 단계적 게이팅을 매니페스트 레벨에서 지원하면 사고를 줄일 수 있다
- **개발 빌드 ↔ 라이브 빌드 분리**: 같은 클라이언트가 환경에 따라 다른 매니페스트 URL을 보도록 설정
