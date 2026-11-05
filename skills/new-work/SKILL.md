---
name: new-work
description: 워크스페이스에서 work(작업 폴더)를 만들고, 묶고, 보관한다. "새 작업 만들어줘", "work 생성", "작업 하나 파줘", "하위 작업 만들어줘", "이 작업 끝났어/보관해줘", "work 묶어줘"처럼 작업 폴더·브랜치·워크트리를 만들거나 옮길 때 사용한다.
---

# work 관리

직접 폴더나 워크트리를 만들거나 옮기지 말고 항상 아래 스크립트를 쓴다. 스크립트는 agent-harness 플러그인의 `bin/`에 있고 플러그인이 켜진 세션에서는 PATH에 있다. 워크스페이스 루트는 환경변수 `AGENT_WORKSPACE_ROOT`로 정한다(비어 있으면 스크립트가 멈춘다). 스크립트가 워크트리 연결, `AGENTS.md` 링크, Claude 세션 폴더(`/resume` 목록)를 함께 맞춘다.

워크스페이스 구조(`repository/`·`work/`·`arxiv/`)가 없거나 `AGENT_WORKSPACE_ROOT`가 비어 있으면 [workspace 스킬](../workspace/SKILL.md)로 먼저 구조를 만든다.

## 규칙

1. work = 폴더 + `task.md`. 레포 워크트리는 그 work에 자기 브랜치가 필요할 때만 둔다.
2. work 안에 work(하위 work)를 둘 수 있다. 모양은 같다. 하위 work는 레포 없이 부모 워크트리에서 작업해도 되고, 병렬로 다른 브랜치가 필요하면 자기 워크트리를 가진다.
3. 세션은 그 work 폴더에서 연다. 세션은 폴더 단위로 묶이므로 `/resume`이 그 작업의 세션만 보여 준다.
4. 이름: slug는 영어 소문자 kebab-case, 3~4단어 이내. 티켓 번호는 넣지 않는다(브랜치명과 `task.md`에 남긴다).
   - work(단일·하위 모두): `MMDD-slug` (시작 월일, 예: `1027-hotfix-x`, `checkout-revamp/1015-api`). 스크립트가 붙인다.
   - 묶음 work(`--group`): slug만. 하위 work는 부모 이름을 반복하지 않는다.
   - 단일 work가 묶음이 되면 `work-move`로 날짜를 뗀다. 연도는 `arxiv/<YYYY-MM>/`와 `task.md`의 시작일로 안다.
5. `work/`에는 진행 중인 것만 둔다. 끝나면(머지·배포 완료 또는 중단) 워크트리를 지우고 문서만 `<워크스페이스>/arxiv/<YYYY-MM>/<work/ 아래 경로>`로 옮긴다(`archive-work`). 코드는 원본 레포의 브랜치에 남는다. 보류는 진행 중으로 두고 `task.md`에 사유를 적는다.
6. 각 work의 `AGENTS.md` 첫 줄은 가장 가까운 상위 `AGENTS.md`(부모 work 또는 루트) 링크다. 스크립트와 SessionStart 훅이 맞춰 준다.

```
work/
├─ checkout-revamp/             묶음 work
│  ├─ task.md
│  ├─ 1015-api/                 하위 work (자기 워크트리)
│  │  ├─ task.md
│  │  └─ web-app/
│  └─ 1027-stg-feedback/        하위 work (task.md만, 부모나 형제 워크트리에서 작업)
└─ 1027-some-hotfix/            단일 work

arxiv/2026-10/                  보관 (문서만, work/ 밖)
├─ 1014-deploy-prd-solutions/
└─ checkout-revamp/0922-first-build/  하위 work는 부모 경로를 유지
```

## 새 work

사용자에게 확인할 것 (이미 말한 것은 다시 묻지 않는다):

1. 작업 요약 → slug 제안 (사용자 확정)
2. 기존 work의 하위인지(`--in`), 하위 work를 담을 묶음인지(`--group`). 관련 묶음이 있으면 `--in`을 제안한다.
3. 대상 레포와 레포별 새 브랜치명(`type/topic` 또는 `<티켓>-type/topic`, 예: `PROJ-123-feat/x`), 기준 브랜치. 레포가 필요 없으면 생략한다. 기준 브랜치를 모르면 `git -C repository/<레포> branch -r`로 확인해 제안하고, 최신 기준이 필요하면 먼저 `fetch origin`을 한다. 레포가 `repository/`에 없으면 [workspace 스킬](../workspace/SKILL.md) 2절(`add-repo`)로 먼저 들인다.

```
new-work --dry-run [--group | --in <부모 work>] <slug> [<레포>:<새 브랜치>:<기준 브랜치> ...]
```

`--dry-run`으로 계획을 보여 주고, 사용자가 확인하면 같은 인자로 다시 실행한다.

스크립트가 하는 일:

- `work/MMDD-<slug>/`(단일), `work/<slug>/`(묶음), `work/<부모>/MMDD-<slug>/`(하위) 폴더, `AGENTS.md`(상위 링크), `task.md`(작업 폴더·시작일·빈 양식)
- 레포마다 `git worktree add -b <새 브랜치> <기준 브랜치>`
- `.env`: 원본 레포에 있으면 **복사**한다. 하나의 `.env`에서 prd/stg 블록 주석을 토글해 환경을 바꾸므로, 링크로 공유하면 한 work의 환경 변경이 다른 work로 번진다.
- `node_modules`: 원본 레포에 있으면 `repository/<레포>/node_modules`로 링크한다. 없으면 만들지 않는다.

끝난 뒤 알릴 것: 만든 경로와 브랜치, `.env`는 생성 시점 스냅샷이라는 것, 링크한 `node_modules`는 의존성이 다른 브랜치에서 충돌할 수 있다는 것(그 경우 링크를 지우고 직접 설치), 설치는 하지 않았다는 것.

## 옮기기·묶기

단발 work가 길어져 묶음 아래로 넣거나 이름을 바꿀 때:

```
work-move --dry-run <work> <새 경로>
```

새 묶음이 필요하면 먼저 `new-work --group <묶음 slug>`로 만들고 옮긴다. 옮기면 `task.md`의 작업 폴더 줄도 새 경로로 고쳐진다. 다만 그 폴더에서 돌던 세션·dev 서버의 경로가 깨지므로, 먼저 `lsof -d cwd | grep <경로>`로 쓰는 프로세스가 없는지 확인한다.

## 보관

```
archive-work --dry-run [--month YYYY-MM] <work>
```

- 보관 전에 확인한다: 미커밋 변경이나 어느 원격에도 없는 커밋(`git rev-list --count HEAD --not --remotes`)이 있으면 끝난 것으로 보지 않고 사용자에게 묻는다. dry-run 출력에 둘 다 나온다.
- 워크트리마다 그 work의 `task.md` "보관 기록"에 남기고 워크트리를 지운다: 레포·브랜치·HEAD·upstream·미push·미커밋, 시작 지점(reflog), 이 브랜치에서 만든 커밋 목록(merge 제외), PR(번호·상태·대상·커밋 수·링크, 브랜치에서 커밋을 못 찾으면 PR의 커밋). 마지막에 폴더에 남는 산출물 목록을 적는다. `.graft-data`·`node_modules`도 지운다.
- 그래도 미커밋 변경이 있으면 `<폴더>.uncommitted.patch`로 남긴다(`git apply`로 되살린다). 어느 브랜치에도 없는 detached HEAD는 `archive/<work>-<폴더>` 브랜치로 남긴다.
- 문서는 `<워크스페이스>/arxiv/<월>/<work/ 아래 경로>`로 옮긴다. 월은 기본으로 이번 달. 같은 달에 같은 묶음의 하위 work가 먼저 보관돼 있으면 합친다.
- 브랜치는 지우지 않는다. 다시 작업하려면 새 work를 만들어 그 브랜치를 워크트리로 연다.

## 하지 않는 일

- commit, push, PR 생성. 사용자 승인이 필요한 별도 단계다.
- 사용자 확인 없이 work를 보관하거나 지우는 일.
