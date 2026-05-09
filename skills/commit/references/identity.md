# 커밋 계정 검증

저장소에 커밋을 올리기 전에, 현재 사용 가능한 git identity가 그 저장소의 *기존 작업 기여자* 중 하나인지 확인해야 한다. 이건 사용자의 명시 요구사항이다 — 엉뚱한 계정으로 남의 저장소에 커밋이 들어가는 사고를 막기 위함이다.

## 핵심 규칙

1. **"자격 있는 계정"** = 그 저장소의 `git log`에 author로 등장한 적 있는 (이메일, 이름) 페어.
2. 현재 effective identity가 그 목록에 있으면 그대로 진행.
3. 없으면, 후보 중 가장 자주(또는 최근) 등장한 계정을 보여주고 사용자에게 어느 걸로 커밋할지 물어본다.
4. 선택한 identity는 **이 커밋에만** 임시 적용한다. 절대 `git config`를 영구히 바꾸지 않는다.

## 절차

### 1. 저장소의 자격 있는 계정 목록 추출

```sh
git -C "$REPO" log --format='%ae|%an' | sort | uniq -c | sort -rn
```

출력 예:
```
  120 alice@example.com|Alice Kim
   34 bob@example.com|Bob Park
    2 ci-bot@noreply.github.com|github-actions[bot]
```

봇 계정(`*[bot]`, `*noreply*`, `ci-*`)은 후보에서 제외하는 게 안전하다 — 사람이 실수로 봇 identity로 커밋하는 걸 방지.

저장소에 커밋이 하나도 없으면(첫 커밋) 자격 목록이 비어 있다 → **사용자에게 어떤 identity로 첫 커밋을 만들지 묻는다**. 임의 가정 금지.

### 2. 현재 effective identity 확인

```sh
git -C "$REPO" var GIT_AUTHOR_IDENT
```

출력 형식: `Name <email> timestamp tz`. 여기서 `Name`과 `<email>`을 추출한다.

(또는 `git -C "$REPO" config user.email`, `user.name`을 따로 읽어도 된다. `var GIT_AUTHOR_IDENT`는 환경변수 `GIT_AUTHOR_*` 오버라이드까지 반영한다.)

### 3. 일치 검사

추출한 (email, name)이 자격 목록의 어느 한 항목과 *이메일 기준* 일치하면 OK. 이름은 표기가 자주 바뀌므로(존칭, 영문/한글) 이메일만 비교하는 게 실용적이다.

일치하지 않으면 다음 단계로.

### 4. 사용자에게 묻기

자격 목록에서 가장 자주 등장한 상위 3-5개를 보여주고 어느 걸 쓸지 선택받는다. 또는 사용자가 새로운 identity를 직접 입력할 수도 있게 한다(드물지만 첫 커밋이 사용자 본인일 때 등).

```
이 저장소의 기존 author 목록에 현재 git config 계정(<현재>)이 없습니다.
어떤 identity로 커밋할까요?

  1) Alice Kim <alice@example.com>     (커밋 120)
  2) Bob Park <bob@example.com>         (커밋 34)
  3) 새로 입력
  4) 취소
```

`AskUserQuestion` 도구를 쓸 때는 위 후보들을 옵션으로 제시한다.

### 5. 임시 오버라이드로 커밋

선택한 identity로 *이 커밋만* 만들기:

```sh
git -C "$REPO" \
    -c "user.email=$EMAIL" \
    -c "user.name=$NAME" \
    commit -m "$MSG"
```

또는 환경변수로:

```sh
GIT_AUTHOR_NAME="$NAME" GIT_AUTHOR_EMAIL="$EMAIL" \
GIT_COMMITTER_NAME="$NAME" GIT_COMMITTER_EMAIL="$EMAIL" \
git -C "$REPO" commit -m "$MSG"
```

`-c`를 쓰면 author + committer 둘 다 그 값으로 들어간다. 환경변수 방식은 둘을 명시적으로 지정해야 한다. 둘 중 어느 쪽이든 OK.

**주의: `git config user.email/name`을 직접 수정하지 않는다** — 사용자가 명시적으로 영구 변경하라고 한 게 아니면 글로벌/로컬 config는 그대로 둔다.

### 6. 한 세션 내 캐싱

같은 저장소에서 연달아 여러 커밋(예: prefix별 분할 커밋, 또는 `/commit-all`의 한 저장소 처리)을 만들 때 매번 묻지 않는다. 사용자가 한 번 선택한 identity를 그 저장소에 대해 세션 내에서 재사용한다.

## 안티-패턴 (하지 말 것)

- 자격 목록에 없는 계정으로 그냥 커밋해버리기 → 사고.
- 글로벌 `git config user.email/name`을 임의로 바꾸기 → 사용자 다른 작업 망가뜨림.
- 봇/CI 계정을 자동 선택 → 사람 작업으로 위장.
- "기본값으로 가장 많이 나온 계정 자동 사용" — 자격 목록에 사용자 외 다른 사람이 있으면 사용자 의도와 다를 수 있음. 반드시 명시 확인.
