---
name: maxplan
description: 소속된 프로젝트에서 기능 한 건을 끝까지 책임지고 마무리하는 6-에이전트 오케스트레이션 워크플로우. Operator(지휘) + Prefab(프리팹 분석) + Feature(구현) + Integration(컨벤션 일원화) + Optimization(최적화) + Log(작업 로그 통합). 사용자가 `/maxplan` 으로 호출하거나, "이 기능 풀로 만들어줘", "처음부터 끝까지 해줘", "프리팹 분석부터 최적화까지", "맥스플랜", "max plan", "오퍼레이터 모드", "전체 워크플로우로", "한 번에 다 해줘" 같은 표현으로 단순 코드 한 줄짜리 작업이 아닌 **요구사항 수집 → 프리팹/아키텍처 파악 → 구현 → 컨벤션 검증 → 최적화** 흐름이 필요한 작업을 요청할 때 자동 적용. 작은 버그 수정·단일 변수 추가·이미 다 정해진 한 줄 변경에는 사용하지 않는다.
---

# /maxplan — 6-에이전트 풀 워크플로우

소속된 프로젝트의 한 기능을 **요구사항부터 최적화까지 한 번에** 가져가는 워크플로우. 너(현재 turn의 Claude)는 이 skill이 발동하는 순간부터 **OperatorAgent** 역할이 된다. 다른 5개 agent는 모두 `Agent` 도구로 spawn 하는 sub-agent.

## 왜 이 skill인가

일반 대화형 모드는 "사용자가 묻고 코드를 짠다" 한 사이클로 끝나는데, 실제 기능 추가는 **요구 명확화 → 프리팹 구조 파악 → 구현 → 컨벤션·과설계 검증 → 최적화** 5단계가 모두 필요하다. 이 skill 은 그 5단계를 명시적 phase 로 끊고, 각 phase 를 전담 sub-agent 에게 넘겨 *Operator 의 컨텍스트가 오염되지 않게* 한다. 그 결과 마지막에 LogAgent 가 한 번에 깔끔한 작업 보고서를 남긴다.

## 6개 에이전트 한눈에

| 이름 | 누가 실행 | 역할 |
|---|---|---|
| **OperatorAgent** | 너 (skill 발동된 현재 turn) | 사용자 인터뷰, phase 지휘, 결과 검토, 다음 phase 결정 |
| **PrefabAgent** | sub-agent | 대상 프리팹의 GameObject/Component 구조 명세서 작성 |
| **FeatureAgent** | sub-agent | 요구사항 → 동작하는 코드. **정확성 최우선** |
| **IntegrationAgent** | sub-agent | 과설계·컨벤션 일탈 교정. **기능 변경 금지** |
| **OptimizationAgent** | sub-agent | `/simplify` → GC/알고리즘 최적화. **기능 변경 금지** |
| **LogAgent** | sub-agent (마지막 1회) | 모든 phase 노트를 한 파일로 통합해서 `Library/MaxPlanLogs/<timestamp>.md` 에 기록 |

각 sub-agent 의 정확한 prompt 템플릿은 [agents/](agents/) 에 있다. spawn 할 때 그 파일을 읽고 `{{placeholder}}` 를 채워 그대로 prompt 로 넘긴다.

## 진행 순서

```
Phase 0  Operator: skill 발동 즉시 컨텍스트 문서 빠르게 스캔 + 작업 로그 시작
Phase 1  Operator: 요구사항 인터뷰 → 모호점 질문 → 요구사항 재확인 (선택 모달로 제공 예 or 아니오 or Others submit 구조)
Phase 2  (조건부) PrefabAgent: 대상 프리팹 구조 분석
Phase 3  FeatureAgent: 기능 구현 (Operator 가 검토 → 최대 1회 재요청)
Phase 4  IntegrationAgent: 컨벤션·과설계 검증·교정
Phase 5  (선택) OptimizationAgent: 사용자 동의 후 /simplify + 추가 최적화
Phase 6  LogAgent: 누적된 phase 노트로 최종 로그 파일 작성
```

각 phase 종료 시 Operator 는 한 줄짜리 **phase 노트** 를 in-context 메모에 적어둔다 (사용자에게는 그대로 표시). 이 노트들이 Phase 6 에서 LogAgent 에 넘어간다.

---

## Phase 0 — 컨텍스트 로딩 + 로그 시작

skill 발동 직후 너가 가장 먼저 하는 일.

1. **타임스탬프 생성** — `yyyyMMdd_HHmmss` 형식 (예: `20260521_143022`). 이걸 이 세션의 `LOG_ID` 로 고정. 모든 phase 노트는 이 LOG_ID 의 로그 파일로 들어간다.
2. **`Library/MaxPlanLogs/` 디렉토리 확보** — 없으면 만든다. (`Library/` 는 Unity 가 관리하는 폴더라 .gitignore 대상이지만, 임시 적재용 로그는 여기가 맞다.)
3. **참조 문서 머리에 올리기** — 다음을 *얕게* 훑는다 (전체 정독은 phase 가 요구할 때):
   - `.claude/CLAUDE.md` — 프로젝트 규칙·아키텍처 패턴
   - `skills/Architecture.md` — 데이터 구조체 시그니처
   - `skills/CodeConvention.md` — 명명·포매팅 규칙
   - `wiki/` 의 디자인 회의록 (특히 `GStack_Office_Hours_*.md`)
4. **사용자에게 첫 응답** — "Phase 0 완료, 인터뷰 시작합니다" 정도. 길게 안 쓴다.

---

## Phase 1 — 요구사항 인터뷰

Operator(너) 가 직접 한다. sub-agent 안 쓴다.

1. 사용자가 처음 던진 요청에서 **확실한 것 / 모호한 것** 을 분리.
2. 모호한 것은 `AskUserQuestion` 으로 묻는다. 다음은 **항상** 명시적으로 확보해야 하는 정보:
   - 대상 시스템/기능 이름 (예: "영웅의 길 노드 추가")
   - **프리팹 작업 여부** — 있으면 정확한 프리팹 경로 (예: `Assets/A_Prefabs/A_Popup/Growth/PopupGrowth.prefab`)
   - 기존 코드를 어디까지 손대도 되는지 (특히 다른 팀원 영역 — `project_division_of_labor` 메모리 참고)
   - 데이터 모델 변경 필요 여부 (Spec/UserData)
3. 모든 답을 받았으면 **요구사항 요약을 한 번 더 사용자에게 재확인** — "정리하면 X, Y, Z 하는 거 맞으시죠?" 형태. **여기서 사용자가 OK 해야 Phase 2 로 넘어간다.**
확인은 선택 모달로 선택지를 제공받는다. 제공 예 or 아니오 or Others submit 구조
4. **Phase 1 노트** 저장: `{requirements_summary, target_prefab_path_or_null, user_confirmed: true}`

---

## Phase 2 — 프리팹 구조 분석 (조건부)

대상 프리팹이 있을 때만. 없으면 건너뛴다.

1. [agents/prefab-agent.md](agents/prefab-agent.md) 를 읽고 `{prefab_path}`, `{requirements_summary}` 를 채워 prompt 작성.
2. `Agent` 도구로 `subagent_type=general-purpose` spawn. 결과는 **프리팹 명세서** (markdown).
3. PrefabAgent 가 컴포넌트 이름이 불명확하다고 보고하면 — Operator 가 그 질문을 사용자에게 그대로 전달해서 답을 받고, 보강한 명세서를 (필요하면) 재요청.
4. **Phase 2 노트** 저장: `{prefab_spec_summary, unclear_questions_raised: [...]}`

---

## Phase 3 — 기능 구현

1. [agents/feature-agent.md](agents/feature-agent.md) 를 읽고 `{requirements_summary}`, `{prefab_spec_or_null}` 을 채워 prompt 작성.
2. `Agent` spawn. 결과는 **변경된 파일 목록 + 핵심 변경 요약**.
3. **Operator 검토 — 한 번**: 결과가 요구사항을 충족했나? 빠진 게 있나? 충족하면 바로 Phase 4. 안 됐으면 *구체적인 부족 지점* 을 명시해서 FeatureAgent 한 번 더 spawn (총 최대 2회). 그래도 안 되면 사용자에게 보고.
4. **Phase 3 노트** 저장: `{files_changed: [...], iterations: 1 or 2, final_status}`

> **재요청은 최대 1회**. 같은 sub-agent 를 3번 이상 부르고 있으면 prompt 자체가 잘못된 거니까 멈추고 사용자에게 상의.

---

## Phase 4 — 컨벤션·일원화 검증

1. [agents/integration-agent.md](agents/integration-agent.md) 를 읽고 `{files_changed}`, `{requirements_summary}` 를 채워 prompt 작성.
2. `Agent` spawn. IntegrationAgent 는 변경 파일을 읽고 **(a) 과설계 (b) 컨벤션 일탈 (c) 프로젝트 패턴과의 불일치** 를 잡아 *직접 수정* 한다. **기능 동작은 그대로** 가 절대 조건.
3. 결과: **무엇을 고쳤는지 diff 수준 요약**.
4. **Phase 4 노트** 저장: `{integration_fixes: [...]}`

---

## Phase 5 — 최적화 (선택)

1. **사용자에게 동의 구함** — `AskUserQuestion` 으로 "최적화 phase 진행할까요?" 묻는다. 기본값은 진행 권장하되 사용자가 거절하면 바로 Phase 6.
2. 동의하면 [agents/optimization-agent.md](agents/optimization-agent.md) 를 읽고 `{files_changed_after_integration}` 채워 spawn.
3. OptimizationAgent 는 `/simplify` skill 을 먼저 적용한 뒤, 추가로 GC(ArrayPool/ListPool/Span)·알고리즘 개선 가능한 부분을 *기능 동등성* 을 지키며 적용. **기능 동작은 그대로**.
4. **Phase 5 노트** 저장: `{optimizations_applied: [...], skipped_reason: null or "user declined"}`

---

## Phase 6 — 로그 통합

1. [agents/log-agent.md](agents/log-agent.md) 읽고 누적된 phase 노트 전부 + 각 sub-agent 가 돌려준 핵심 요약을 prompt 에 채운다.
2. `Agent` spawn. LogAgent 는 `Library/MaxPlanLogs/<LOG_ID>.md` 한 파일을 작성한다. 형식은 [templates/log-template.md](templates/log-template.md) 참고.
3. Operator 는 사용자에게 **로그 파일 경로 + 작업 한줄 요약** 으로 마무리 응답.

---

## 진행 중 원칙

- **사용자 합의 우선** — Phase 1 의 요구사항 재확인, Phase 5 의 최적화 동의는 *반드시* 사용자 답을 받고 진행. 다른 phase 는 자율 진행.
- **Operator 가 sub-agent 결과를 받아 사용자에게 재포장** — sub-agent 가 돌려준 raw 응답을 그대로 사용자에게 던지지 않는다. Operator 가 한 번 거르고 1~3문장으로 요약.
- **TodoWrite 로 phase 추적** — 6 phase 를 TodoList 로 만들어두고 각 phase 시작/종료 시 갱신. 사용자가 진행 상태를 본다.
- **각 phase 노트는 짧게** — 1~3 bullet. 통합 로그에서 sub-agent 의 자세한 출력은 따로 첨부되므로, 노트 자체는 *Operator 가 무엇을 결정했고 왜* 만 담는다.
- **메모리 우선** — 작업 도중 `feedback_*` / `project_*` 메모리에 적힌 규칙(예: `feedback_no_overengineering_substitution`, `project_division_of_labor`, `feedback_no_helper_state`) 에 어긋나는 sub-agent 결과가 나오면 Operator 가 잡아낸다.

---

## phase 노트 in-context 포맷

각 phase 끝날 때 너가 메모리에 적어두는 형태. 마지막 Phase 6 에서 LogAgent 에 통째로 전달한다.

```
[Phase N] <phase name>
- decision: <Operator 가 무엇을 결정했는지>
- subagent_summary: <sub-agent 가 돌려준 핵심 1~2줄>
- files_touched: [path1, path2, ...]   (해당 phase 에서)
- followup_needed: <있으면, 없으면 null>
```

이걸 Phase 0~5 모두에 대해 누적해두고 Phase 6 에 한꺼번에 LogAgent prompt 에 박는다.

---

## 발동 안 함

다음 같은 단순 작업에는 이 skill 을 발동하지 않는다. 일반 대화로 처리.

- 한 줄 변경 / 변수 rename / 오타 수정
- 단일 파일 버그 추적 (→ `investigate` 같은 다른 skill)
- 단순 질의응답, 코드 설명
- 이미 사용자가 정확히 어떻게 고칠지 다 정해서 던진 작업

이런 작업에 풀 워크플로우를 돌리면 비용·지연만 늘고 사용자가 답답해진다.
