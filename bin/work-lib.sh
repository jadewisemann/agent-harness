# work 스크립트와 훅이 함께 쓰는 함수. source 해서 쓴다.
# work 규칙: work = 폴더 + task.md (+ 필요하면 레포 워크트리). work 안에 work를 둘 수 있다.
# 끝난 work는 <워크스페이스>/arxiv/<YYYY-MM>/<work/ 아래 경로> 로 옮긴다.
# 워크스페이스 루트는 환경변수 AGENT_WORKSPACE_ROOT 로 정한다.

die() { echo "오류: $*" >&2; exit 1; }

[ -n "${AGENT_WORKSPACE_ROOT:-}" ] || die "AGENT_WORKSPACE_ROOT 가 비어 있다. 워크스페이스 루트의 절대 경로로 설정한다."
ROOT=${AGENT_WORKSPACE_ROOT%/}
W="$ROOT/work"
A="$ROOT/arxiv"
REPO="$ROOT/repository"
CLAUDE_PROJECTS="$HOME/.claude/projects"

# 절대 경로로 바꾼다. 상대 경로는 현재 폴더 → work/ 순서로 찾는다.
work_abs() {
  local p=$1
  case "$p" in /*) ;; *) if [ -e "$PWD/$p" ]; then p="$PWD/$p"; else p="$W/$p"; fi ;; esac
  (cd "$p" 2>/dev/null && pwd -P) || die "폴더가 없다: $1"
}

# 경로 안에 있는 워크트리 루트들 (.git 파일). node_modules와 레포 내부는 보지 않는다.
work_worktrees() {
  find "$1" \( -name node_modules -o -name .git -type d \) -prune -o -name .git -type f -print 2>/dev/null |
    while read -r g; do dirname "$g"; done
}

# 경로가 속한 work 폴더(work/ 또는 arxiv/<월>/ 아래). 레포 안이면 그 레포를 품은 폴더, 기준 폴더 자체면 빈 값.
work_of() {
  local d=$1 w=$1 base
  case "$d" in
    "$W"/*) base=$W ;;
    "$A"/*/*) base="$A/$(printf '%s' "${d#"$A"/}" | cut -d/ -f1)" ;;
    *) return 0 ;;
  esac
  while [ "$d" != "$base" ] && [ "$d" != / ]; do
    [ -e "$d/.git" ] && w=$(dirname "$d")
    d=$(dirname "$d")
  done
  [ "$w" = "$base" ] && return 0
  echo "$w"
}

# work의 AGENTS.md 첫 줄이 가장 가까운 상위 AGENTS.md(부모 work 또는 루트)를 가리키게 한다.
work_link_agents() {
  local dir=$1 p f rel link first tmp
  p=$(dirname "$dir")
  while [ "$p" != "$ROOT" ] && [ ! -f "$p/AGENTS.md" ]; do p=$(dirname "$p"); done
  rel=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$p/AGENTS.md" "$dir")
  link="@$rel"
  f="$dir/AGENTS.md"
  if [ ! -f "$f" ]; then
    printf '%s\n\n# 작업 지침\n' "$link" > "$f"
    return
  fi
  first=$(head -n 1 "$f")
  [ "$first" = "$link" ] && return
  tmp=$(mktemp)
  if [[ "$first" =~ ^@.*AGENTS\.md$ ]]; then
    { echo "$link"; tail -n +2 "$f"; } > "$tmp"
  else
    { printf '%s\n\n' "$link"; cat "$f"; } > "$tmp"
  fi
  cat "$tmp" > "$f"; rm -f "$tmp"
}

# Claude 세션 폴더 이름 (경로의 영숫자 외 문자를 - 로 바꾼 것)
claude_enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

# work 폴더를 옮긴다: mv → 워크트리 연결 복구 → AGENTS.md 링크 → Claude 세션 폴더 이름 변경.
# 세션 폴더는 새 이름으로 옮기고 옛 이름은 링크로 남긴다(/resume 유지).
work_move() {
  local src=$1 dst=$2 dry=${3:-0} d rel old new wt common
  [ -e "$dst" ] && die "이미 있다: $dst"
  local sessions=()
  while read -r d; do
    rel=${d#"$src"}
    old="$CLAUDE_PROJECTS/$(claude_enc "$d")"
    new="$CLAUDE_PROJECTS/$(claude_enc "$dst$rel")"
    [ -d "$old" ] && [ ! -L "$old" ] && sessions+=("$old|$new")
  done < <(find "$src" -maxdepth 3 \( -name node_modules -o -name .git -o -name .graft-data \) -prune -o -type d -print)

  echo "이동: ${src#"$ROOT"/} → ${dst#"$ROOT"/}"
  for s in "${sessions[@]+"${sessions[@]}"}"; do echo "    세션: $(basename "${s%%|*}") → $(basename "${s##*|}")"; done
  [ "$dry" = 1 ] && return 0

  mkdir -p "$(dirname "$dst")"
  mv "$src" "$dst"
  while read -r wt; do
    common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "    경고: 워크트리 확인 실패 $wt" >&2; continue; }
    git -C "$(dirname "$common")" worktree repair "$wt" >/dev/null 2>&1 || echo "    경고: worktree repair 실패 $wt" >&2
  done < <(work_worktrees "$dst")
  work_link_agents "$dst"
  while read -r d; do
    d=$(dirname "$d")
    [ "$d" != "$dst" ] && [ "$(work_of "$d")" = "$d" ] && work_link_agents "$d"
  done < <(find "$dst" \( -name node_modules -o -name .git -o -name .graft-data \) -prune -o -name task.md -print)
  # task.md의 "작업 폴더: <워크스페이스 기준 경로>" 줄을 새 경로로 고친다(하위 work 포함).
  # sed -i 는 macOS와 GNU의 문법이 달라 임시 파일로 바꾼다.
  find "$dst" \( -name node_modules -o -name .git -o -name .graft-data \) -prune -o -name task.md -print0 |
    while IFS= read -r -d '' f; do
      sed "s#^작업 폴더: ${src#"$ROOT"/}#작업 폴더: ${dst#"$ROOT"/}#" "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
    done
  for s in "${sessions[@]+"${sessions[@]}"}"; do
    old=${s%%|*}; new=${s##*|}
    [ -L "$new" ] && rm "$new"  # 예전 이동이 남긴 링크 자리면 실제 폴더로 바꾼다
    if [ -e "$new" ]; then echo "    경고: 세션 폴더가 이미 있어 옮기지 않음 $(basename "$new")" >&2; continue; fi
    mv "$old" "$new" && ln -s "$new" "$old"
  done
}

# 보관 기록: 브랜치의 시작 지점(reflog), 이 브랜치에서 만든 커밋, PR을 markdown 목록으로 출력한다.
#   work_branch_record <원본 레포> <브랜치 또는 빈 값(detached)> <HEAD> <upstream 또는 ->
work_branch_record() {
  local main=$1 br=$2 sha=$3 up=$4 first base from trunk range n slug names nm u prs
  if [ -z "$br" ]; then
    echo "- 커밋: detached HEAD \`$sha\` (브랜치 없음)"
    echo "- PR: 없음"
    return 0
  fi
  first=$(git -C "$main" reflog show --format='%H%x09%gs' "refs/heads/$br" 2>/dev/null | tail -1)
  trunk=$(git -C "$main" for-each-ref --format='%(refname)' refs/remotes/origin/develop refs/remotes/origin/main refs/remotes/origin/master 'refs/remotes/origin/deploy/*' | tr '\n' ' ')
  base=${first%%$'\t'*}
  from=${first#*$'\t'branch: Created from }
  if [ -z "$first" ]; then
    echo "- 시작: reflog 없음. develop·main·deploy/* 에 없는 커밋을 적는다"
    range="refs/heads/$br --not $trunk"
  elif [ "$from" = "origin/$br" ] || [ "$from" = "$up" ]; then
    # 이미 원격에 있던 브랜치를 받아 시작했으면, 시작 전 커밋도 이 작업의 것이라 트렁크 기준으로 센다
    echo "- 시작: 원격 브랜치 \`$from\`를 받아 시작. develop·main·deploy/* 에 없는 커밋을 적는다"
    range="refs/heads/$br --not $trunk"
  else
    echo "- 시작: ${first#*$'\t'branch: } (\`$(git -C "$main" rev-parse --short "$base")\`)"
    range="$base..refs/heads/$br"
  fi
  # shellcheck disable=SC2086
  n=$(git -C "$main" rev-list --count --first-parent --no-merges $range)
  if [ "$n" = 0 ]; then
    echo "- 커밋: 없음"
  else
    echo "- 커밋 ${n}개 (merge 제외, 이 브랜치에서 만든 것):"
    # shellcheck disable=SC2086
    git -C "$main" log --first-parent --no-merges --format='  - `%h` %s' $range | head -100
    [ "$n" -gt 100 ] && echo "  - … (100개까지만 적음)"
  fi
  # origin 이 없는 레포(add-repo --new 등)도 멈추지 않게 실패를 빈 값으로 둔다
  slug=$( { git -C "$main" remote get-url origin 2>/dev/null || true; } | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')
  names=$br
  case "$up" in origin/*)
    u=${up#origin/}
    case "$u" in develop|main|master|deploy/*|release*|"$br") ;; *) names="$names $u" ;; esac ;;
  esac
  if ! command -v gh >/dev/null || [ -z "$slug" ]; then echo "- PR: 확인 못 함"; return 0; fi
  prs=""
  for nm in $names; do
    prs+=$(gh pr list --repo "$slug" --head "$nm" --state all --limit 20 \
      --json number,state,baseRefName,title,url,commits \
      --jq '.[] | "  - #\(.number) \(.state) → \(.baseRefName) (커밋 \(.commits | length)개): \(.title) \(.url)"' 2>/dev/null) || { echo "- PR: 확인 못 함 (gh 오류)"; return 0; }
    prs+=$'\n'
  done
  prs=$(printf '%s' "$prs" | sed '/^$/d' | sort -u)
  if [ -z "$prs" ]; then echo "- PR: 없음"; return 0; fi
  echo "- PR:"; echo "$prs"
  # 브랜치에서 커밋을 못 찾았으면(이미 트렁크에 머지됨 등) PR의 커밋을 적는다
  if [ "$n" = 0 ]; then
    for nm in $(echo "$prs" | sed -nE 's/^  - #([0-9]+) .*/\1/p'); do
      echo "- PR #$nm 커밋:"
      gh pr view "$nm" --repo "$slug" --json commits --jq '.commits[] | "  - `\(.oid[0:9])` \(.messageHeadline)"' 2>/dev/null | head -100
    done
  fi
}

# 보관 기록의 산출물: work 폴더에 남는 파일·폴더 (지침·도구 설정·워크트리·하위 work 제외)
work_outputs() {
  local w=$1 e b out=""
  for e in "$w"/* "$w"/.[!.]*; do
    [ -e "$e" ] || continue
    b=$(basename "$e")
    case "$b" in task.md|AGENTS.md|AGENTS.override.md|.agents|.codex|.DS_Store|.graft-data|node_modules) continue ;; esac
    [ -f "$e/.git" ] && continue
    [ -f "$e/task.md" ] && continue
    [ -d "$e" ] && b="$b/"
    out="$out${out:+, }\`$b\`"
  done
  echo "${out:-없음}"
}

# 보관 전 정리: 경로 안의 워크트리마다 기록(브랜치·HEAD·미push·미커밋·시작 지점·커밋·PR)을 그 work의
# task.md "보관 기록"에 남기고, 미커밋 변경은 <폴더>.uncommitted.patch 로 저장한 뒤 워크트리를 지운다.
# 브랜치는 원본 레포에 남는다. 어느 브랜치에도 없는 detached HEAD는 archive/<work>-<폴더> 브랜치로 남긴다.
# 캐시(.graft-data, node_modules)도 지운다.
work_strip() {
  local dir=$1 dry=${2:-0} wt w rel main repo br sha up ahead n keep patch idx f today cell works=""
  today=$(date +%Y-%m-%d)
  local wts=()
  while read -r wt; do wts+=("$wt"); done < <(work_worktrees "$dir")
  for wt in "${wts[@]+"${wts[@]}"}"; do
    w=$(work_of "$(dirname "$wt")"); [ -n "$w" ] || w=$(dirname "$wt")
    rel=${wt#"$w"/}
    main=$(dirname "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)")
    repo=$(basename "$main")
    br=$(git -C "$wt" branch --show-current)
    sha=$(git -C "$wt" rev-parse --short HEAD)
    up=$(git -C "$wt" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo -)
    ahead=$(git -C "$wt" rev-list --count HEAD --not --remotes)  # 어느 원격에도 없는 커밋
    n=$(git -C "$wt" status --porcelain | awk '!/ node_modules$/ && !/ \.env$/' | wc -l | tr -d ' ')
    keep=""
    if [ -z "$br" ] && [ -z "$(git -C "$wt" for-each-ref --contains HEAD --count=1 --format=x refs/heads refs/remotes)" ]; then
      keep="archive/$(basename "$w")-$(basename "$wt")"
    fi
    patch=""; [ "$n" -gt 0 ] && patch="$(echo "$rel" | tr / -).uncommitted.patch"
    echo "  ${wt#"$ROOT"/}: ${br:-detached} $sha, upstream $up, 미push $ahead, 미커밋 $n${patch:+ → $patch}${keep:+, 브랜치 $keep 생성}"
    [ "$dry" = 1 ] && continue

    [ -n "$keep" ] && git -C "$main" branch "$keep" "$(git -C "$wt" rev-parse HEAD)"
    if [ -n "$patch" ]; then
      idx=$(mktemp)
      GIT_INDEX_FILE=$idx git -C "$wt" read-tree HEAD
      GIT_INDEX_FILE=$idx git -C "$wt" add -A -- . ':(exclude)node_modules' ':(exclude).env'
      GIT_INDEX_FILE=$idx git -C "$wt" diff --cached --binary HEAD > "$w/$patch"
      rm -f "$idx"
    fi
    f="$w/task.md"; [ -f "$f" ] || printf '# %s\n' "$(basename "$w")" > "$f"
    grep -q '^## 보관 기록' "$f" || printf '\n## 보관 기록 (%s)\n\n워크트리는 지웠다. 브랜치·커밋은 원본 레포 `repository/<레포>`에 남아 있다. 미push는 어느 원격에도 없는 커밋 수다.\n' "$today" >> "$f"
    cell=$n; [ -n "$patch" ] && cell="${n}건 → \`$patch\`"
    {
      printf '\n### %s — %s `%s`\n\n' "$rel" "$repo" "${keep:-${br:-detached}}"
      printf -- '- HEAD `%s`, upstream `%s`, 미push %s, 미커밋 %s\n' "$sha" "$up" "$ahead" "$cell"
      if [ -n "$keep" ]; then work_branch_record "$main" "" "$sha" "$up"; else work_branch_record "$main" "$br" "$sha" "$up"; fi
    } >> "$f"
    case $'\n'"$works"$'\n' in *$'\n'"$w"$'\n'*) ;; *) works="$works${works:+$'\n'}$w" ;; esac
    git -C "$main" worktree remove --force "$wt" || echo "    경고: 워크트리 삭제 실패 $wt" >&2
  done
  [ "$dry" = 1 ] && return 0
  find "$dir" \( -name .graft-data -o -name node_modules \) -prune -exec rm -rf {} + 2>/dev/null || true
  while read -r w; do
    [ -n "$w" ] && printf '\n### 산출물\n\n%s\n' "$(work_outputs "$w")" >> "$w/task.md"
  done <<< "$works"
}
