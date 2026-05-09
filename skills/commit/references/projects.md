# 프로젝트 후보 찾기

`/commit`이나 `/commit-all`이 동작할 후보 git 저장소들을 어떻게 찾는지 정의한다. macOS와 Windows 모두 지원해야 한다.

## 출처 (우선순위 순)

1. **Fork의 `repositories.toml`** — Fork(GUI)가 추적하는 저장소 목록.
   - macOS: `~/Library/Application Support/com.DanPristupov.Fork/repositories.toml`
   - Windows: `%APPDATA%\Fork\repositories.toml` (보통 `C:\Users\<user>\AppData\Roaming\Fork\repositories.toml`)
   - 형식 예시:
     ```toml
     source_dirs = ["/Applications/"]
     scan_depth = 5
     ignore = []

     [[repository]]
     path = "/Users/foo/Desktop/project-a"
     opened = 1778336620

     [[repository]]
     path = "/Users/foo/code/project-b"
     opened = 1778334947
     ```
   - `path`는 절대경로, `opened`는 Unix timestamp(Fork에서 마지막에 연 시각).

2. **GitHub Desktop 추적 DB** (있으면 보조 출처):
   - macOS: `~/Library/Application Support/GitHub Desktop/`
   - Windows: `%APPDATA%\GitHub Desktop\`
   - 보통 SQLite로 저장되며 형식이 버전마다 변할 수 있어, 단순 텍스트 파싱으로 안전하게 뽑기 어려우면 무시한다(에러 내지 말 것).

3. **사용자 등록 파일** (위 둘이 빈 경우 또는 명시 등록):
   - `~/.claude/skills/commit/projects.txt`
   - 한 줄에 하나씩 절대경로(또는 `~/...` 확장 가능 경로). 빈 줄과 `#` 시작 라인은 무시.

세 출처를 합쳐 중복 제거(절대경로 정규화 후 기준)한 목록을 후보로 삼는다.

## 후보 검증

각 후보 경로에 대해:
- 디렉토리가 실제로 존재하고 `<path>/.git`이 있어야 한다 (디렉토리 또는 gitfile).
- 없거나 git 저장소가 아니면 조용히 제외한다(목록이 오래되어 사라진 저장소가 있을 수 있음).

## "최근 수정된 프로젝트" 결정

`/commit`이 git 저장소가 아닌 위치에서 호출됐을 때 사용한다. 후보들 중 다음 기준으로 가장 최근 것을 고른다 (우선순위 순):

1. **변경사항이 있는 저장소만 1차 필터** — `git -C <path> status --porcelain`이 비어있지 않은 것만 후보.
2. **워킹트리 mtime의 최댓값** — 추적 중인 파일들의 mtime 중 가장 최근 시각. 빠른 근사로는 `find <path> -type f -not -path '*/.git/*' -newer <reference> -print -quit` 또는 단순히 `stat -f %m` (macOS) / `stat -c %Y` (Linux)을 디렉토리 자체에 적용. Windows에서는 PowerShell `Get-ChildItem -Recurse | Sort LastWriteTime`.
3. 동률이면 Fork `opened` 값이 큰 쪽.

후보가 0개면 사용자에게 알리고 멈춘다 — 임의로 짐작해 커밋하지 않는다.

## "커밋할 수 있는 프로젝트" (commit-all용)

위 후보 목록 중 **변경사항이 있는** 모든 저장소(`git status --porcelain`이 비어있지 않은 것). 변경이 없으면 그 저장소는 건너뛴다.

## 셸 스니펫 — Fork toml 파싱 (macOS/Linux bash)

`tomllib` 같은 외부 의존 없이 처리하려면 grep/awk만으로 충분하다(형식이 단순하므로):

```sh
TOML="$HOME/Library/Application Support/com.DanPristupov.Fork/repositories.toml"
# Windows에서는 "$APPDATA/Fork/repositories.toml" 또는 cygpath/MSYS 경로 변환
if [[ -f "$TOML" ]]; then
    awk '
        /^\[\[repository\]\]/ { in_repo = 1; path = ""; opened = 0; next }
        in_repo && /^path *= */ { gsub(/^path *= *"|"$/, ""); path = $0 }
        in_repo && /^opened *= */ { gsub(/^opened *= */, ""); opened = $0 }
        in_repo && /^$/ { if (path != "") print opened "\t" path; in_repo = 0 }
        END { if (in_repo && path != "") print opened "\t" path }
    ' "$TOML"
fi
```

각 줄이 `<opened>\t<path>` 형식. 정렬은 `sort -nr`로 최근 순.

awk 파싱이 깨지는 toml(예: 따옴표가 없는 path, 멀티라인 값)이면 Python으로 fallback해도 좋다 — `python3 -c "import tomllib,sys,json; print(json.dumps(tomllib.load(open(sys.argv[1],'rb'))))" <toml>` (Python 3.11+) 또는 `python3 -c "import tomli,sys,json; ..."`(3.10 이하).

## Windows 메모

- 경로 구분자: PowerShell 사용을 권장. `$env:APPDATA`로 AppData 경로를 얻는다.
- git 명령 자체는 동일하게 동작하지만, 셸 스니펫은 Bash 가정이므로 Windows에서는 PowerShell 등가물을 작성해야 할 수 있다. 사용자에게 일단 macOS 기준 로직으로 동작 후 Windows에서 막히면 그때 보완하겠다고 알리는 것도 한 방법이다.
