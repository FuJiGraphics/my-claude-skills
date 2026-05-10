---
name: nserver-spec-data
description: NServer 패키지(`Brainworks.NServer.SpecScriptableData`)의 자동 생성 파이프라인용 구글 시트를 만들거나 편집할 때 컨벤션을 적용한다. 시트명에 `Spec` 안 붙이기, 빈 시트(헤더만) 안 만들기, 셀에 JSON 박지 않기, 첫 행이 타입을 결정한다는 원칙, 콤마 csv / 평행 csv / 외래키 multi-row 의 배열 표현 패턴을 강제. 사용자가 "스펙 데이터", "스펙 시트", "구글 시트 가져오기", "SpecScriptableData", "NServer 시트" 등의 표현으로 NServer 의 spec 데이터 시트를 디자인·등록·수정하려 할 때 자동 적용.
---

# nserver-spec-data

NServer 패키지(`Brainworks.NServer.SpecScriptableData`) 의 자동 생성 파이프라인이 어떻게 동작하는지, 그래서 시트를 어떻게 짜야 하는지의 영구 지침. **이 컨벤션을 어기면 자동 생성이 망가지거나 빈 클래스가 만들어진다.**

자동 생성 진입점은 Unity 의 메뉴 `NServer/구글 시트 가져오기`. 이 메뉴가 무엇을 보고 코드를 만드는지 정확히 알아야 시트를 잘 짤 수 있다.

---

## 자동 생성 파이프라인 한눈에

```
[Apps Script doGet] ────GET────► JSON {시트명: [{...row...}, ...], ...}
                                       (한글/NOEX_ 시트는 응답에 안 옴)
   │
   ▼
[GoogleSheetSpecImporter.GenerateCSharpClass]
   - 시트명 그대로 className
   - {className}SpecScriptableData.cs   ←── Spec 자동 추가
   - {className}SpecData.cs              ←── Spec 자동 추가
   - 첫 행(rows[0]) 의 column 목록으로 필드 정의
   - 모든 row 의 같은 컬럼 타입 살펴 promote (int → float → string)
   │
   ▼
[CreateGoogleSheetSO] (컴파일 후 메뉴 재실행 시)
   - reflection 으로 _list 채워 .asset 생성
   - {outputFolder}/{className}SpecScriptableData.asset
```

**런타임 시작 시**는 다른 경로:
```
NServer.SpecData.LoadSpecAsync
  → Firebase Storage 의 {className}{N}.csv 다운로드
  → SpecScriptableData.PopulateFromJson(JArray)
  → Init() 훅 (사람이 추가한 dict 빌드 등)
```

에디터/런타임 두 경로 모두 같은 `SpecScriptableData._list` 를 채우는 게 목표.

---

## 절대 지켜야 할 컨벤션

### 1. 시트 이름 — `Spec` 접미사 절대 X

자동 생성기가 `{시트명}SpecScriptableData` / `{시트명}SpecData` 로 변환한다. 시트명에 `Spec` 박으면 클래스명에 `Spec` 두 번 들어간다.

| ✅ 좋은 시트명 | → 자동 생성 | ❌ 나쁜 시트명 | → 자동 생성 |
|---|---|---|---|
| `Hero` | `HeroSpecScriptableData` | `HeroSpec` | `HeroSpecSpecScriptableData` |
| `SinsuSkill` | `SinsuSkillSpecScriptableData` | `SinsuSkillData` | `SinsuSkillDataSpecScriptableData` |
| `Stage` | `StageSpecScriptableData` | `StageScriptableData` | `StageScriptableDataSpecScriptableData` |

규칙:
- **PascalCase 명사** (`Hero`, `Sinsu`, `Stage`, `BoxInfo`, `SinsuSkill`)
- **`Spec` / `Data` / `ScriptableData` 같은 접미사 일체 금지**
- **한글 이름 / `NOEX_` 접두사** → Apps Script 가 export 에서 제외 (개발용/임시 데이터). 운영 시트는 영문 PascalCase.

### 2. 빈 시트 만들지 X — 데이터 있을 때만 시트 생성

TeamBattle 의 21개 시트 모두 최소 1행 이상 데이터가 있다. **헤더만 있는 시트는 만들지 않는다.**

이유:
- `GenerateCSharpClass` 가 `rows[0].properties` 를 순회해 필드를 정의 — `rows[0]` 가 없으면 빈 SpecData 클래스가 만들어지고 끝
- 운영 의미도 없음 (불러올 데이터 0건)

도메인의 첫 데이터가 아직 없으면 **시트 자체를 만들지 말 것**. 첫 데이터가 등장할 때 시트를 추가한다.

placeholder 로 헤더만 등록하고 싶은 충동은 잘못된 본능. 안 만든다.

### 3. 셀은 스칼라만 — JSON 박지 X

자동 생성기는 `JTokenType` 을 보고 필드 타입을 정한다. 지원되는 타입은:

| JSON | C# 필드 |
|---|---|
| Integer | `int` |
| Float | `float` |
| Boolean | `bool` |
| String / 그 외 | `string` |
| 빈 셀 (`""`) | `string` |

JSON 객체나 배열을 셀에 통째로 박으면 자동 생성기는 그 컬럼을 그냥 `string xxxJson` 으로 매핑한다. 런타임에서 따로 `JObject.Parse` 해서 풀어야 하므로 컨벤션 위반.

### 4. 배열 표현 — 두 가지 컨벤션 + 자동 생성기 한계

⚠ **가장 중요한 사실**: `GoogleSheetSpecImporter.GenerateCSharpClass` 는 **`List<T>` 자동 매핑을 지원하지 않는다.** 추론 분기 (`GoogleSheetSpecImporter.cs:411-420`):

```csharp
case JTokenType.Integer: return "int";
case JTokenType.Float:   return "float";
case JTokenType.Boolean: return "bool";
default:                 return "string";   // ← Array, Object 등 모두 string
```

따라서 **시트에서 배열로 보낸 데이터든 콤마 csv 셀이든, 자동 생성기가 만드는 필드는 `public string xxx;` 하나로 끝난다.** SO 채울 때도 `JArray.ToString()` 으로 직렬화돼 `"[100,200,300]"` 같은 문자열 한 개가 string 필드에 들어간다.

진짜 `List<T>` 로 쓰려면 다음 중 하나:
- 사람이 자동 생성된 `*SpecData.cs` 의 필드 타입을 `string` → `List<T>` 로 바꾸고 (다음 import 시 덮어써짐 — partial 분리 권장), Init() 에서 헬퍼로 빌드
- 자동 생성된 string 은 그대로 두고 `*SpecScriptableData.Init()` 에 헬퍼 메서드 추가 (`GetXxxList()` 류)

#### (A) 콤마 csv (TeamBattle 정공법, 단순)

가장 흔한 패턴. 한 셀에 콤마로 묶어 string 으로 export, 런타임에서 사람이 풀어쓴다.

| 패턴 | 시트 표현 | 런타임 파싱 |
|---|---|---|
| 단일 배열 | `needPieces: "10,20,30,40"` | `Utils.ConvertArrayStringToList<int>(s, ",")` |
| 객체 배열 (평행 csv) | `needItem: "Jewel,Gold"` + `needItemCnt: "100,1000"` | 두 csv 를 풀어 인덱스로 zip |
| 자식 가변 길이 / 자식 컬럼 多 | 별도 시트 + 외래키 | `Init()` 에서 `Dictionary<FK, List<row>>` 빌드 |

자동 생성된 클래스에서 해당 컬럼은 `string` 으로 매핑됨. 사람이 후속으로 헬퍼 메서드 추가해 List<T> 로 풀어쓴다. enum 은 string 필드로 두고 후속 수정.

#### (B) `arrN_xxx` 컬럼 packing (Apps Script 가 진짜 JSON 배열로 export)

배열을 평면 컬럼 여러 개로 펼치는 패턴. **Apps Script 의 export 가 정규식으로 N 캡처해 진짜 JSON 배열로 만들어준다.**

```
시트 헤더: arr0_value, arr1_value, arr2_value
첫 행:     100,        200,        300
   ↓ Apps Script export
JSON:    { "value": [100, 200, 300] }   ← key 는 _ 뒤 부분, 진짜 array
```

규칙:
- **0-indexed 권장**: `arr0_v, arr1_v, arr2_v` → `[v0, v1, v2]`
- **같은 N 에 다른 이름** = 평행 배열 두 개:
  `arr0_a, arr0_b, arr1_a, arr1_b` → `arr_a: [a0, a1]`, `arr_b: [b0, b1]`
- **N 누락** 은 null 패딩: `arr0_v + arr2_v` → `[v0, null, v2]`
- 자동 생성기는 array 를 `JTokenType.Array → default: string` 으로 매핑 (사람이 후속에서 `List<T>` 로 변경)

언제 (B) 를 쓰나: 길이가 거의 고정이고 디자이너가 시트에서 컬럼별로 보기 편한 경우 (예: 5단계 강화 수치). 가변/긴 배열은 (A) csv 가 더 자연스럽다.

⚠ (B) 도 (A) 와 마찬가지로 자동 생성된 필드는 `string` 한 개. 결과 string 의 형식만 다르다 — (A) 는 `"100,200,300"`, (B) 는 `"[100,200,300]"` (JSON 배열 문자열). 둘 다 사람이 후속 헬퍼로 풀어쓴다. 일관성 관점에서 **TeamBattle 은 (A) csv 만 사용** — 새 NServer 프로젝트도 특별한 이유 없으면 (A) 로 통일.

#### ⚠ `arr` 헤더 위험지대 — Apps Script export 깨짐

다음 헤더는 **doGet 응답 전체를 HTML 에러 페이지로 만든다** (정규식이 N 매치 실패 → `match[1]` null 액세스 → 크래시 → 모든 시트 import 실패):

| ❌ 깨뜨리는 헤더 | 이유 |
|---|---|
| `arr_value` | `arr` + `_` + 이름 인데 N 캡처 자리에 비숫자 |
| `arr_1`, `arr_2` | `arr_` 다음 숫자 (정규식이 N 자리 헷갈림) |
| `arr` 단독 | N 매치 실패 |
| `arrXyz_value` | N 자리에 알파벳 (정규식 실패) |

**가장 안전한 룰**: 일반 컬럼명에는 `arr` 접두사를 쓰지 않는다. `arr` 로 시작할 거면 반드시 `arr{숫자}_{이름}` 형태로만.

실수 회복: 깨뜨리는 헤더가 들어간 시트를 `delete_sheet` 또는 헤더 수정 → doGet 정상화.

#### 중첩 배열 (배열의 배열)

TeamBattle 에 사례 없음. **하지 말 것** — 별도 시트 + 외래키 multi-row 로 풀어라.

### 5. 첫 행이 타입 sentinel — 신중히 작성

자동 생성기는 첫 행의 셀 타입을 보고 컬럼 타입을 추론한다.

- **모든 컬럼에 의미 있는 값** 넣기. 빈 셀은 영영 `string` 으로 추론.
- **bool 필드**: 시트의 체크박스 또는 대문자 `TRUE` / `FALSE` 사용 (소문자 `true`/`false` 는 시트 export 에 따라 string 으로 갈 수 있음)
- **정수 필드**: 셀 포맷이 "Plain text" 가 아닌지 확인 (Plain text 면 JSON string 으로 export)
- **두 가지 bool 값을 모두 등장시키려면** 첫 행에 두 행을 작성 (예: ScoreBoard 의 isStartNode=TRUE 와 isCrown=TRUE 두 행을 모두 첫 행 영역에 둔다)

### 6. 외래키 + Init() 패턴 (자식 시트)

자식이 가변 개수면 별도 시트 + 외래키. 자동 생성된 클래스는 `_list` 만 가지므로 사람이 후속으로 dict 빌드 헬퍼 추가:

```csharp
// 자동 생성된 SinsuSkillSpecScriptableData.cs 를 사람이 수정 (또는 partial 로 보강)
public override void Init() {
    base.Init();
    _dictBySinsuType = _list
        .GroupBy(d => d.sinsuType)
        .ToDictionary(g => g.Key, g => g.OrderBy(d => d.starLevel).ToList());
}

public SinsuSkillSpecData GetSkill(eSinsuType type, int starLevel) =>
    _dictBySinsuType.TryGetValue(type, out var list) && starLevel <= list.Count
        ? list[starLevel - 1] : null;
```

자동 생성된 부분 (`_list` 필드, `*SpecData` 타입) 은 다음 import 시 덮어써지므로 사람의 수정은 partial / 별도 헬퍼 메서드로 분리.

### 7. 절대 금지 (체크리스트)

- ❌ 시트명에 `Spec` / `Data` / `ScriptableData` 접미사
- ❌ 빈 시트 (헤더만)
- ❌ 셀에 JSON 객체/배열 통째로
- ❌ 첫 행에 빈 셀 또는 모호한 타입
- ❌ 한 시트에 형식이 다른 여러 종류 행 (도메인 섞기)
- ❌ 한 셀 안에 nested csv (예 `"a|b,c|d"`) — 별도 시트로 풀어라

---

## 새 도메인 시트 추가 절차

도메인 `Foo` 의 첫 데이터를 등록할 때:

1. **시트 이름 결정** — `Foo` (Spec 접미사 X). 한글/NOEX_ X.
2. **헤더 + 최소 1행 작성**:
   - 컬럼명은 camelCase (`fooId`, `level`, `desc`)
   - 모든 컬럼에 의미 있는 값
   - bool 은 체크박스/대문자 `TRUE`/`FALSE`
   - 배열은 콤마 csv (`"1,2,3"`)
3. **시트 업로드** (`replace_sheet` webhook 또는 NServer 시트 편집기 → Upload)
4. **Unity 에서 `NServer/구글 시트 가져오기`** 메뉴 클릭
   - `Foo.json` + `FooSpecScriptableData.cs` + `FooSpecData.cs` 자동 생성
   - 컴파일 후 한 번 더 클릭 → `FooSpecScriptableData.asset` 생성
5. **사람이 후속 수정**:
   - enum 필드 필요 시 `public string fooType;` → `public eFooType fooType;`
   - dict 빌드 / 헬퍼 메서드 추가 (partial 또는 같은 파일)
6. **`SpecManager` (또는 `MN<Module>`) 등록** — 호출부 단일 진입점

---

## 디버그 — 자동 생성기가 이상하면

| 증상 | 원인 |
|---|---|
| `XxxSpecSpecScriptableData` (Spec 두 번) | 시트명에 `Spec` 들어감 |
| 빈 SpecData 클래스 (필드 없음) | 시트가 헤더만 / `rows[0]` 없음 |
| `string xxxJson` 만 있는 컬럼 | 셀에 JSON 박음 |
| `string` 인데 `int` 가 의도였음 | 첫 행이 빈 셀 또는 Plain text 포맷 |
| 시트가 import 안 됨 | 시트명이 한글 또는 NOEX_ 접두사 |

---

## 참조 — 잘 짜인 사례 (`Zillion/TeamBattle`)

- `Hero` (32행 × 16칼럼) — 평면, scalar 만
- `Sinsu` (5행 × 6칼럼) → `SinsuSkill` (30행 × 11칼럼, 외래키 `sinsuType`) — 부모-자식 multi-row
- `Stage` (15행 × 6칼럼) — 콤마 csv 의 정석 (`heroType: "Warrior1, Mage2"`)
- `Exchange` (8행 × 6칼럼) — 평행 csv (`needItem` + `needItemCnt`)
- `Relic` (10행 × 6칼럼) — 단일 csv 배열 (`needPieces: "4,5,6,7,8"`)
- `Item` (199행 × 5칼럼) — 모든 도메인이 참조하는 마스터 시트

자동 생성된 결과 클래스 (`Zillion/TeamBattle/Assets/A_Data/SpecJson/*.cs`) 와 함께 보면 패턴을 빠르게 익힐 수 있다.

---

## 관련 코드

- `Packages/com.brainworks.nserver/Editor/GoogleSheetSpecImporter.cs` — 자동 생성기 본체
- `Packages/com.brainworks.nserver/Runtime/Data/SpecScriptableData.cs` — 베이스 클래스
- `Packages/com.brainworks.nserver/Runtime/Services/NSpecData.cs` — 런타임 로더
- `Assets/A_Scripts/Ingame/Core/Utils.cs` (TeamBattle) — `ConvertArrayStringToList<T>` 헬퍼
