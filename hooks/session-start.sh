#!/bin/bash
# 플러그인 SessionStart 훅. 워크스페이스(AGENT_WORKSPACE_ROOT) 아래에서 시작한 세션에만 안내를 출력한다.
# AGENT_WORKSPACE_ROOT 가 비어 있거나 워크스페이스 밖이면 아무것도 출력하지 않는다.
[ -n "${AGENT_WORKSPACE_ROOT:-}" ] || exit 0
ROOT=${AGENT_WORKSPACE_ROOT%/}
PLUGIN=$(cd "$(dirname "$0")/.." && pwd -P)
input=$(cat)
read -r cwd source < <(printf '%s' "$input" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print(d.get("cwd") or "-", d.get("source") or "-")' 2>/dev/null)
[ "$cwd" = "-" ] && cwd=
cwd=${cwd:-$PWD}
case "$cwd" in "$ROOT"|"$ROOT"/*) ;; *) exit 0 ;; esac

# work 아래에서 시작하면 그 work의 AGENTS.md 첫 줄이 가장 가까운 상위 AGENTS.md(부모 work 또는 루트)를
# 가리키도록 보장한다. 파일이 없으면 만들고, 링크가 없거나 낡았으면 고친다.
. "$PLUGIN/bin/work-lib.sh"
w=$(work_of "$cwd")
[ -n "$w" ] && [ -d "$w" ] && work_link_agents "$w" 2>/dev/null

# /refresh 기록 파일: 루트는 work/orchestrator.md, work 아래는 그 work의 task.md.
# 이어받기 메모가 남아 있으면(=/refresh 1절 뒤 아직 2절을 안 함) 시작 맥락에 넣는다. 대화를 되살리는 resume은 뺀다.
record=
if [ "$cwd" = "$ROOT" ]; then record="$ROOT/work/orchestrator.md"
elif [ -n "$w" ]; then record="$w/task.md"
fi
[ "$source" = resume ] && record=

python3 - "$record" "$ROOT" "$PLUGIN" <<'PY'
import json, os, re, sys
record, root, plugin = sys.argv[1], sys.argv[2], sys.argv[3]
graft = ("[graft] 이 워크스페이스의 레포(repository/*, work/<work>/<repo>)는 코드 검색에 graft를 우선 사용한다. "
         "레포 안에는 파일을 만들지 않으므로 직접 graft를 실행하지 말고 래퍼를 쓴다: "
         "`" + plugin + "/bin/graft-here <레포 경로> <ask|grep|callers|skeleton|map|blast> [인자]`. "
         "그래프가 없거나 낡았으면 래퍼가 먼저 빌드한다(<work>/.graft-data/<repo>). 영어 식별자 키워드가 더 잘 맞는다. 필요하면 grep을 써도 된다.")
parts = []
memo = None
if record and os.path.isfile(record):
    text = open(record, encoding="utf-8").read()
    m = re.search(r"^## 이어받기 메모[ \t]*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if m:
        memo = m.group(1).strip()
if memo:
    rel = os.path.relpath(record, root)
    parts.append(
        "[/refresh 이어받기] 이 세션은 `/refresh`로 대화를 비운 뒤 다시 시작했다. 정본은 `" + rel + "`와 아래 메모다.\n"
        "- 첫 사용자 메시지가 무엇이든(인사·질문 포함) 먼저 `" + plugin + "/skills/refresh/SKILL.md` 2절 \"다시 읽기\"를 그대로 수행하고, 그 결과로 답한다.\n"
        "- 이 시작 맥락에 함께 들어온 claude-mem 내용(Work state 목록, recent context 관찰 기록)은 이어받기에 쓰지 않는다. "
        "낡았거나 다른 세션 것이 섞여 있다. 사용자가 따로 물을 때만 참고한다.\n"
        "- 메모 속 세션이 이 세션이 아닌 것 같으면(오케스트레이터 줄 등) 이어받기 전에 사용자에게 묻는다.\n\n"
        "## 이어받기 메모 (" + rel + ")\n" + memo)
parts.append(graft)
parts.append("[agent-harness] 하네스 스킬 파일은 `" + plugin + "/skills/<orchestrate|refresh|new-work|workspace>/SKILL.md`에 있다. "
             "work 스크립트(new-work·archive-work·work-move·add-repo·workspace-init·graft-here)는 PATH에 있다.")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": "\n\n".join(parts)}}, ensure_ascii=False))
PY
