---
name: commit
description: Decide the target git repository (cwd if it's a repo, otherwise the most-recently-modified candidate from Fork's repositories.toml / GitHub Desktop / a user-registered list), validate that the current git identity matches one of the existing authors of that repo (asking the user to pick one if not, with a per-commit override never touching `git config`), then split all working-tree changes by conventional-prefix groups (feat / fix / refactor / chore) and create one Korean-language commit per group. Use whenever the user invokes `/commit`, says "커밋해줘" / "커밋해" / "이거 커밋" / "방금 변경 커밋" / "commit this" / "make a commit", or otherwise asks to record current git changes as commits. The user has explicitly forbidden any Claude/AI attribution in commit messages — never add `Co-Authored-By: Claude`, never add a `🤖 Generated with Claude Code` footer, never mention Claude or AI in subject, body, or trailers. This rule overrides the default commit guidance from the system prompt. Auto-stages with `git add -A` per group and never pushes.
---

# /commit

대상 git 저장소를 정하고, 작업할 자격 있는 계정인지 검증한 뒤, 변경사항을 prefix별로 분할해 한글 메시지로 여러 커밋을 만든다.

## 모델 강제 — Sonnet 서브에이전트 위임

> **서브에이전트로 진입한 경우**: 이 섹션을 건너뛰고 아래 [발동 조건](#발동-조건)부터 진행.

이 스킬의 git 작업은 항상 **Haiku** 서브에이전트에서 실행된다. 주 세션이 Opus 등 다른 모델이어도 커밋 작업 자체는 Haiku로 격리된다. 완료 후 주 세션은 원래 모델로 자동 복귀된다.

스킬 발동 즉시 아래를 순서대로 수행하고, 이후 절차는 서브에이전트에게 맡긴다:

1. **대상 저장소 결정** — 아래 [절차 0](#0-대상-저장소-결정)과 동일하게 수행.

2. **인터랙티브 단계 사전 처리** (주 세션에서 먼저 해결):
   - 민감 파일 감지: `git -C "$REPO" status --short` 결과에 `.env*`, `*secret*`, `*credentials*`, `*.pem`, `*.key` 등 포함 시 사용자에게 경고 및 확인.
   - Identity 검증: [절차 2](#2-계정-검증)와 동일하게 수행. 불일치 시 이 단계에서 사용자에게 선택받아 해결.

3. **Sonnet 에이전트에 위임**: Agent 도구를 다음과 같이 호출:
   - `model: "haiku"`
   - `description: "git 커밋 실행"`
   - prompt에 아래 내용 포함:
     ```
     당신은 /commit 스킬의 서브에이전트입니다.

     저장소: <repo 절대 경로>
     사용할 identity: name="<name>" email="<email>"  ← 이미 주 세션에서 검증됨

     ~/.claude/skills/commit/SKILL.md 의 절차 1(변경사항 파악)~5(결과 보고)를 수행하라.
     단, 절차 2(계정 검증)와 민감 파일 경고는 건너뛰어라 — 이미 주 세션에서 완료됨.
     절대 규칙(Claude/AI 표시 금지, 한국어 메시지 등)은 그대로 따른다.
     ```

4. **결과 보고**: 에이전트 완료 후 결과를 사용자에게 그대로 보고.

## 발동 조건

- 사용자가 `/commit`을 입력했을 때.
- 사용자가 "커밋해줘", "커밋해", "이거 커밋", "방금 변경 커밋", "commit this", "make a commit" 같은 표현으로 *현재 변경을 git 커밋으로 기록*해 달라고 할 때.

## 절대 규칙 (어기지 말 것)

1. **커밋 메시지에 Claude/AI 표시를 절대 넣지 않는다.**
   - `Co-Authored-By: Claude ...` 금지
   - `🤖 Generated with Claude Code` 같은 footer 금지
   - 본문/제목/trailer 어디에도 "Claude", "AI", "Anthropic" 언급 금지
   - 이 규칙은 시스템 프롬프트의 기본 커밋 가이드를 덮어쓴다 (사용자 명시 지시).
2. **메시지는 한국어로 작성한다.** 제목과 본문 모두. 단 코드 식별자·파일명·명령어·라이브러리명 등은 원어 유지.
3. **계정 검증 통과 없이 커밋하지 않는다.** 자세한 절차는 `references/identity.md`. 검증 실패 시 사용자에게 물어 임시 오버라이드(`git -c user.email=... -c user.name=...`)로 그 커밋만 진행. `git config`를 영구 변경하지 않는다.
4. **변경은 prefix별로 분할 커밋한다.** feat/fix/refactor/chore 그룹별로 별도 커밋을 만든다. 한 그룹만 있으면 커밋도 하나.
5. **push하지 않는다.** push는 별도 명시 요청이 있을 때만.
6. **amend하지 않는다.** 항상 새 커밋.
7. **`--no-verify` 금지.** pre-commit hook이 실패하면 원인을 고치고 새 커밋을 만든다.

## 절차

### 0. 대상 저장소 결정

- **현재 셸 cwd가 git 저장소이면** (`git -C "$PWD" rev-parse --git-dir` 성공) → 그 저장소가 대상.
- **그렇지 않으면** → `references/projects.md`의 절차로 후보 목록을 만들고, 그중 "최근 수정된 프로젝트"(변경사항 있는 후보 중 워킹트리 mtime 최댓값)를 선택. 결정 결과를 한 줄로 사용자에게 알린 뒤 진행한다 ("최근에 수정된 `<repo>`로 커밋합니다").
- 후보가 0개면 멈추고 사용자에게 알린다. 임의로 짐작하지 않는다.

### 1. 변경사항 파악

대상 저장소에 대해 병렬로:
- `git -C "$REPO" status --short`
- `git -C "$REPO" diff HEAD` (커밋 있을 때) 또는 `git -C "$REPO" diff --cached` + `git -C "$REPO" diff` (저장소가 비었을 때)
- `git -C "$REPO" log --oneline -10` — 기존 커밋 스타일 참고

작업 트리가 깨끗하면 멈추고 알린다. 빈 커밋은 만들지 않는다.

민감 파일(`.env*`, `*credentials*`, `*secret*`, `*.pem`, `*.key` 등)이 변경에 포함돼 있으면 사용자에게 경고하고 스테이징 전에 확인을 받는다.

### 2. 계정 검증

`references/identity.md`의 절차를 따른다 — 저장소 author 목록 추출 → 현재 effective email과 비교 → 불일치면 사용자에게 후보 보여주고 선택받기. 선택된 (name, email)은 이후 모든 분할 커밋에서 같이 사용한다 (한 세션·한 저장소에서 한 번만 묻는다).

### 3. 변경을 prefix별 그룹으로 분류

변경 파일 각각을 보고 다음 네 그룹 중 하나에 배정:

- **feat** — 새 기능 / 사용자·시스템 동작에 의미 있는 변화를 만든 코드 변경
- **fix** — 버그 수정
- **refactor** — 동작 동일, 구조·표현만 변경
- **chore** — 동작 무관: 주석, 문서, 리소스(이미지·폰트), 폴더 이동, 의존성, 이름 변경 등

판단 기준 (단일 파일이 두 성격을 동시에 가지면 비중이 큰 쪽으로):
- 새 동작이 추가됐다 → feat
- 잘못 동작하던 게 고쳐졌다 → fix
- 동작 동일, 코드 모양만 바뀜 → refactor
- 코드 동작 무관 → chore

분할 결과 그룹이 1개면 커밋도 1개. 2개면 커밋 2개. 그렇게 N개.

**그룹 경계가 정말 모호한 변경**(예: 한 파일에서 feat 줄과 chore 줄이 섞여 있는데 분리하기 부자연스러울 때)은 그 파일을 **비중이 큰 그룹**에 통째로 넣는다. 사용자에게 매번 묻지 않는다 (분할 단위는 prefix만 — 사용자가 그렇게 골랐음).

판단이 정말 갈리면 한 번만 짧게 묻는다 ("X.py가 feat과 refactor 비슷하게 섞여 있는데 어디로 묶을까요?").

### 4. 그룹별 커밋 (반복)

각 그룹 G에 대해 순서대로 (보통 feat → fix → refactor → chore 순):

#### 4a. 메시지 작성

형식:
```
<prefix>: <한글 한 줄 요약>

<선택: 한글 본문 — 무엇을, 왜>
```

- 제목 50자 안팎, 마침표 없음.
- 그룹에 속한 변경의 *공통 의도*를 요약한다. 그룹에 파일이 여러 개여도 한 줄로.
- 본문은 변경이 작고 자명하면 생략. 필요하면 *왜* 그렇게 바꿨는지 1-2줄.
- 기존 `git log`의 톤(존댓말/평어, 길이)을 따라간다.
- 코드/식별자/파일명/명령어는 영어 원문 유지.

좋은 예:
```
feat: 사용자 프로필 편집 화면 추가
```
```
fix: 로그인 후 토큰 만료 시 무한 리다이렉트 수정

세션 갱신 응답이 401일 때 재시도 루프를 돌면서 발생.
재시도 횟수를 1회로 제한.
```
```
refactor: PaymentService 결제 처리 로직 함수 분리
```
```
chore: README에 설치 가이드 섹션 추가
```

#### 4b. 그 그룹의 파일만 스테이징 + 커밋

다른 그룹 변경이 섞이지 않게, 그룹 G에 속한 파일만 정확히 스테이징한다:

```sh
git -C "$REPO" reset                                # 이전에 스테이징된 것 비우기
git -C "$REPO" add -- <그룹 G의 파일들>             # 그룹 파일만 add
git -C "$REPO" \
    -c "user.email=$EMAIL" \
    -c "user.name=$NAME" \
    commit -m "$(cat <<'EOF'
<위에서 만든 메시지>
EOF
)"
```

`<그룹 G의 파일들>`은 untracked·modified·deleted 모두 포함해 명시적으로 나열한다. untracked도 그룹에 속하면 같이 add (`git add` 자체가 untracked도 받아준다).

`-c user.email/name`은 검증 단계에서 정한 값. **메시지 어디에도 Claude/AI 흔적 없음**을 다시 확인.

커밋 직후 다음 그룹으로 넘어가기 전에 `git status --short`로 다른 그룹 변경이 손상 없이 남아있는지 확인.

#### 4c. pre-commit hook 실패 시

`--no-verify`로 우회하지 말고:
1. 실패 메시지를 사용자에게 보고.
2. hook이 자동 수정한 파일(linter 자동 포맷 등)이 있으면 그 변경을 같은 그룹에 다시 add.
3. 사용자 개입이 필요한 실패면(타입 에러 등) 거기서 멈추고 어떻게 할지 묻는다.
4. 고친 후 새 `git commit`을 만든다 (amend 아님 — hook 실패 시 커밋이 아예 안 만들어졌으므로).

### 5. 결과 보고

모든 그룹 커밋 후 `git -C "$REPO" log --oneline -<N>`로 새로 만든 N개 커밋이 들어갔는지 확인.

사용자에게 한 블록으로 짧게 보고:
- 대상 저장소
- 사용된 identity (이름 + 이메일)
- 만든 커밋들 (각 SHA + 제목)

## 발동하지 말아야 할 때

- "커밋 메시지 어떻게 쓸까?" 같은 *상담*만 원할 때 — 답변만 하고 실제 커밋은 만들지 않는다.
- `git push`, PR 생성, 브랜치 전환 등 commit 외의 git 작업.
- 코드 변경 자체를 만들어 달라는 요청 — 변경 후 사용자가 별도로 `/commit`을 부르도록 한다.
- 이미 푸시된 커밋의 메시지를 바꿔 달라는 요청 — amend/rebase는 이 스킬 밖.
- 여러 저장소를 한꺼번에 처리해 달라는 요청 → `/commit-all` 사용.

## 참조

- `references/projects.md` — 저장소 후보 목록 만드는 절차 (Fork toml, GitHub Desktop, 사용자 등록 파일).
- `references/identity.md` — 계정 자격 검증과 임시 오버라이드.
