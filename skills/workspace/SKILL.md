---
name: workspace
description: 워크스페이스 기본 구조(repository/·work/·arxiv/·log/, 루트 AGENTS.md, work/orchestrator.md)를 만들고, 레포를 repository/ 에 들인다(원격 클론, 흩어진 로컬 레포 옮기기, 새 레포 만들기). "워크스페이스 만들어줘", "구조 잡아줘", "이 서버 세팅", "레포 추가해줘", "이 레포 클론해줘", "새 레포 만들어줘", "~/code 레포들 들여와"처럼 work를 만들기 전의 구조·레포를 다룰 때 사용한다. 작업 폴더(work) 자체는 new-work 스킬이다.
---

# 워크스페이스 구조와 레포

new-work·orchestrate·refresh는 이 구조를 전제로 한다. 구조가 없거나 `AGENT_WORKSPACE_ROOT`가 비어 있으면 그 스킬들보다 이 스킬을 먼저 한다.

```
$AGENT_WORKSPACE_ROOT/
├─ AGENTS.md            공통 지침(템플릿에서 만든 뒤 사용자가 고친다)
├─ repository/<레포>    원본 레포. work의 워크트리는 여기서 연다
├─ work/                진행 중인 작업 (work/orchestrator.md = 루트 오케스트레이터 허브)
├─ arxiv/<YYYY-MM>/     보관된 work
└─ log/YYYY-MM-DD.md    일일 작업 로그
```

스크립트(`workspace-init`, `add-repo`)는 플러그인 `bin/`에 있고 PATH에 있다. 모두 `--dry-run`이 있다. 항상 dry-run 결과를 보여 주고 확인을 받은 뒤 같은 인자로 실행한다.

## 1. 구조 만들기

1. 루트 위치를 사용자에게 확인한다. 이미 레포가 모여 있는 폴더(예: `~/code`)를 루트로 쓸지, 새 폴더를 만들지 묻는다.
2. `workspace-init --dry-run <루트>`. 레포가 다른 폴더에 흩어져 있으면 `--scan <그 폴더>`를 더한다(여러 번 가능). 루트 자체는 `--scan`이 없을 때 기본으로 본다.
3. 확인을 받으면 `workspace-init <루트>`로 만든다. 이미 있는 폴더·파일은 그대로 둔다(덮어쓰지 않음).
4. 알릴 것:
   - `AGENT_WORKSPACE_ROOT`에 넣을 값. 설정 파일(`~/.claude/settings.json`의 `env` 등)은 직접 고치지 않고 넣을 줄을 보여 준다. 설정한 뒤 새 세션부터 훅이 켜진다.
   - 루트 `AGENTS.md`는 템플릿이다. 레포·팀 규칙에 맞게 고칠지 사용자에게 묻는다. 지침 파일이라 사용자가 요청할 때만 고친다.
   - 출력의 "repository/ 밖의 git 레포" 목록. 들이는 것은 2절의 `--from`이고, 레포마다 사용자 확인을 받는다.

## 2. 레포 들이기 (add-repo)

`AGENT_WORKSPACE_ROOT`가 필요하다. 아직 설정 전이면 명령 앞에 `AGENT_WORKSPACE_ROOT=<루트>`를 붙인다.

| 경우 | 명령 |
|---|---|
| 원격 레포 클론 | `add-repo --dry-run [--name <이름>] <원격 URL>` |
| 흩어진 로컬 레포 옮기기 | `add-repo --dry-run [--name <이름>] --from <레포 경로>` |
| 새 레포 | `add-repo --dry-run --new <이름> [--branch main]` |

- 이름은 기본으로 URL·폴더 이름이다. `repository/`에 같은 이름이 있으면 멈춘다.
- `--from`은 폴더를 옮긴다(복사 아님).
  - 옮기기 전에 그 폴더를 쓰는 세션·dev 서버가 없는지 `lsof -d cwd | grep <경로>`로 확인한다. 옮기면 그 경로가 깨진다.
  - 연결된 워크트리는 옮기기 전 경로를 적어 두었다가 새 경로로 `git worktree repair <경로…>`에 넘겨 다시 잇는다(레포 안쪽 `.claude/worktrees/*` 포함). 끝난 뒤 prunable이 남으면 경고한다.
  - Claude 세션 폴더는 새 이름으로 옮긴 뒤 옛 이름을 링크로 남긴다(`/resume` 유지). 다른 레포의 워크트리는 들이지 않는다.
  - 미커밋 변경은 그대로 따라간다. dry-run에 건수가 나온다.
- `--new`는 `git init`과 빈 첫 커밋(`chore: 저장소 생성`)을 만든다. 첫 커밋이 있어야 new-work의 기준 브랜치가 된다.
  - 커밋이므로 dry-run을 보여 줄 때 이 커밋도 확인받는다. 작성자·커미터는 사용자 지침에 정한 값을 쓴다(어긋나면 `GIT_AUTHOR_*`·`GIT_COMMITTER_*` 환경변수).
  - 원격 저장소는 만들지 않는다. GitHub에 만들려면 공개/비공개와 소유자(계정·조직)를 사용자에게 물은 뒤, 승인을 받고 `gh repo create <소유자>/<이름> --private|--public --source <루트>/repository/<이름> --remote origin`을 실행한다. push는 별도 승인이다.
- 끝나면 스크립트가 기준 브랜치 후보와 `new-work` 예시를 보여 준다. 바로 new-work 스킬로 이어 갈 수 있다.

## 하지 않는 일

- 설정 파일(`settings.json`, 셸 프로필) 수정. 넣을 값만 안내한다.
- 사용자 확인 없이 레포를 옮기거나, 원격 저장소를 만들거나, push하는 일.
- `repository/` 안의 레포에서 직접 작업. 작업은 new-work로 워크트리를 열어서 한다.
