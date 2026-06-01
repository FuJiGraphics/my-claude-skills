---
name: commit-all
description: Run the `/commit` workflow against every git repository that currently has uncommitted changes. Discovers candidate repos from Fork's repositories.toml, GitHub Desktop, and the user-registered list (`~/.claude/skills/commit/projects.txt`), filters to those with `git status --porcelain` non-empty, and processes each one in turn — same logic as `/commit` per repo: identity validation against that repo's existing authors, prefix-based split commits (feat/fix/refactor/chore), Korean messages, **no Claude/AI attribution anywhere**, no pushes. Use whenever the user invokes `/commit-all`, says "전체 커밋해줘" / "all repo commit" / "모든 프로젝트 커밋" or otherwise asks to commit pending changes across multiple projects at once.
---

# /commit-all

현재 변경사항이 있는 모든 git 저장소에 대해 `/commit`과 동일한 작업을 차례로 수행한다. 각 저장소마다 그 저장소의 자격 있는 계정으로만 커밋한다.

## 모델 강제 — Sonnet 서브에이전트 위임

> **서브에이전트로 진입한 경우**: 이 섹션을 건너뛰고 아래 [발동 조건](#발동-조건)부터 진행.

이 스킬의 git 작업은 항상 **Haiku** 서브에이전트에서 실행된다. 주 세션이 Opus 등 다른 모델이어도 커밋 작업 자체는 Haiku로 격리된다. 완료 후 주 세션은 원래 모델로 자동 복귀된다.

스킬 발동 즉시 아래를 순서대로 수행하고, 이후 절차는 서브에이전트에게 맡긴다:

1. **후보 저장소 수집 및 필터** — 아래 [절차 1~2](#1-후보-저장소-목록)와 동일하게 수행. 변경사항 있는 저장소 목록을 확정한다.

2. **사용자에게 처리 대상 보여주기** — 아래 [절차 3](#3-사용자에게-처리-대상-보여주기)과 동일하게 수행.

3. **인터랙티브 단계 사전 처리** (주 세션에서 먼저 해결, 저장소별로):
   - 각 저장소의 민감 파일 감지 → 있으면 사용자 확인.
   - 각 저장소의 Identity 검증 (`commit/references/identity.md`) → 불일치 시 이 단계에서 사용자에게 선택받아 해결.
   - 결과를 저장소별 `{repo, name, email}` 목록으로 정리.

4. **Sonnet 에이전트에 위임**: Agent 도구를 다음과 같이 호출:
   - `model: "haiku"`
   - `description: "전체 저장소 git 커밋 실행"`
   - prompt에 아래 내용 포함:
     ```
     당신은 /commit-all 스킬의 서브에이전트입니다.

     처리할 저장소 목록 (identity 이미 검증됨):
       1) <repo1 절대 경로>  →  name="<name1>" email="<email1>"
       2) <repo2 절대 경로>  →  name="<name2>" email="<email2>"
       ...

     ~/.claude/skills/commit-all/SKILL.md 의 절차 4(저장소 단위 순차 처리)~6(최종 보고)를 수행하라.
     각 저장소의 계정 검증과 민감 파일 경고는 건너뛰어라 — 이미 주 세션에서 완료됨.
     절대 규칙(Claude/AI 표시 금지, 한국어 메시지 등)은 그대로 따른다.
     ```

5. **결과 보고**: 에이전트 완료 후 결과를 사용자에게 그대로 보고.

## 발동 조건

- 사용자가 `/commit-all`을 입력했을 때.
- "전체 커밋해줘", "모든 프로젝트 커밋", "여러 저장소 커밋", "all repo commit" 등 *여러 저장소를 한꺼번에 커밋*하는 의도가 명확할 때.

## 절대 규칙

`/commit`과 동일하다 (`commit/SKILL.md` 참조). 핵심만 다시:

1. **Claude/AI 표시 금지** — 메시지 어디에도 "Claude / AI / Anthropic / Co-Authored-By: Claude / Generated with..." 흔적 없음.
2. **메시지는 한국어**.
3. **각 저장소마다 자격 있는 계정 검증** — 그 저장소에 한 번도 커밋한 적 없는 identity로는 커밋하지 않는다. 임시 오버라이드(`-c user.email=... -c user.name=...`)로만 사용, `git config` 영구 변경 금지.
4. **prefix별 분할 커밋** (저장소 안에서 feat/fix/refactor/chore 그룹별).
5. **push하지 않는다.**

## 절차

### 1. 후보 저장소 목록

`commit/references/projects.md`의 절차로 모든 후보 저장소 목록을 수집:
- Fork `repositories.toml`
- GitHub Desktop (있을 때 보조)
- `~/.claude/skills/commit/projects.txt` (사용자 등록)

### 2. "변경사항 있는" 저장소만 필터

각 후보 `<repo>`에 대해 `git -C <repo> status --porcelain`을 실행, 출력이 비어있지 않은 것만 추린다. 비어있으면 "변경 없음"으로 처리하고 건너뛴다.

대상 저장소가 0개면 사용자에게 "변경사항 있는 저장소가 없습니다"라고 알리고 종료.

### 3. 사용자에게 처리 대상 보여주기

처리 시작 전에 한 번 요약해서 보여준다 — 어떤 저장소들에서 무엇을 커밋할지 사용자가 한눈에 보게:

```
처리할 저장소 (변경 요약):
  1) ~/Desktop/Gempiece/The-Genius        — modified: 3, untracked: 1
  2) ~/Desktop/FujiGraphics/my-claude-skills — modified: 3, untracked: 3
```

각 저장소별로 prefix 그룹이 어떻게 나뉠지 미리 분석해 보여줄 필요는 없다 (그건 처리 단계에서). 그냥 "어디에" "대략 얼마나" 손댈지 보이면 충분.

### 4. 저장소 단위로 순차 처리

각 대상 저장소에 대해 순서대로 (보통 mtime 최신 순 — 사용자가 가장 신경 쓰는 것 먼저):

1. 짧은 헤더로 어느 저장소를 처리 중인지 알린다 ("--- <repo> 처리 중 ---").
2. **계정 검증** (`commit/references/identity.md`):
   - 그 저장소의 author 목록 추출.
   - 현재 git effective email이 목록에 없으면 사용자에게 후보 보여주고 선택받기.
   - 선택된 (name, email)은 그 저장소의 모든 분할 커밋에 같이 사용. 한 저장소당 한 번만 묻는다.
3. **변경 분류** — 파일을 feat / fix / refactor / chore 네 그룹으로 배정 (`commit/SKILL.md` 절차 3 참조).
4. **그룹별 커밋** — `git reset` → `git add <그룹 파일>` → `git -c user.email/name commit` 반복 (`commit/SKILL.md` 절차 4 참조).
5. **민감 파일** 발견 시 그 저장소 처리 중에 즉시 사용자에게 경고. 거부하면 그 저장소만 건너뛰고 다음으로 (전체 중단 아님).

### 5. 저장소 사이의 실패 처리

한 저장소 처리에서 실패가 나도(예: 사용자가 계정 선택을 취소, pre-commit hook이 막히는 등) **다른 저장소 처리는 계속한다.** 단:
- 어떤 저장소가 실패했고 왜인지 명확히 기록해두고
- 마지막 보고에서 함께 보여준다.

저장소 N개 중 일부만 성공하는 게 정상적인 결과로 간주된다 — 사용자가 일부는 의도적으로 건너뛸 수도 있고.

### 6. 최종 보고

모든 저장소 처리 후 한 블록으로 정리:

```
완료:
  ~/Desktop/Gempiece/The-Genius (Alice Kim <alice@...>)
    - feat: ... (a1b2c3d)
    - chore: ... (e4f5g6h)

  ~/Desktop/FujiGraphics/my-claude-skills (Bob Park <bob@...>)
    - feat: ... (i7j8k9l)

건너뜀/실패:
  ~/Projects/x — 사용자 계정 선택 취소
  ~/Projects/y — pre-commit hook 실패 (lint error)
```

저장소별 사용된 identity, 만든 커밋 SHA + 제목, 그리고 실패/건너뜀 사유까지.

## 발동하지 말아야 할 때

- 단일 저장소만 다루는 경우 → `/commit` 사용.
- push까지 원할 때 → push는 별도 명시 요청 필요. 이 스킬은 commit까지만.
- "커밋 메시지 좀 봐줘" 같은 *상담* — 답변만 하고 실제 커밋은 만들지 않는다.

## 참조

`/commit`의 모든 세부 절차를 그대로 사용한다 — 중복 작성 대신 그쪽을 참조한다:

- `~/.claude/skills/commit/SKILL.md` — 단일 저장소 절차의 전체 정의.
- `~/.claude/skills/commit/references/projects.md` — 후보 저장소 발견.
- `~/.claude/skills/commit/references/identity.md` — 계정 검증·임시 오버라이드.
