# agent-harness

A Claude Code plugin (and its own marketplace) for running agent sessions inside a shared workspace:

- **`/agent-harness:workspace`** — set up the workspace layout (`workspace-init`) and bring repos into `repository/` by clone, move, or new (`add-repo`)
- **work folders** — one folder + `task.md` per task, with git worktrees for the branches it needs (`new-work`, `work-move`, `archive-work`)
- **`/agent-harness:orchestrate`** — a session that only splits work into sub-sessions, tracks them in `task.md`, and verifies results before reporting
- **`/agent-harness:refresh`** — write a handoff note, clear the conversation, and pick up from the note
- **SessionStart hook** — inside the workspace, keeps each work's `AGENTS.md` linked to its parent and injects a pending `/refresh` handoff note; outside the workspace it prints nothing
- **`graft-here`** — runs `graft` code search against a repo while keeping its graph outside the repo

Skill text is written in Korean.

## Install

```
/plugin marketplace add jadewisemann/agent-harness
/plugin install agent-harness@agent-harness
```

For local testing without installing: `claude --plugin-dir /path/to/agent-harness`.

## Setting up a new machine

1. Install the plugin (above).
2. Create the layout. In a Claude session, ask to set up the workspace (`/agent-harness:workspace`), or run it yourself — the plugin's `bin/` is on the Bash tool's PATH; from a shell use the full path under the plugin directory:

   ```
   workspace-init --dry-run --scan ~/code /path/to/workspace
   workspace-init /path/to/workspace
   ```

   Existing files are never overwritten. Repos found by `--scan` are only listed, not moved.
3. Set `AGENT_WORKSPACE_ROOT` (see Configuration) and start a new session so the hook picks it up.
4. Add repos:

   ```
   add-repo --dry-run git@github.com:<owner>/<repo>.git   # clone
   add-repo --dry-run --from ~/code/<repo>                 # move an existing local repo
   add-repo --dry-run --new <name>                         # new local repo with an empty first commit
   ```

   Drop `--dry-run` to apply. Creating a GitHub repo for `--new` is a separate, manual step (`gh repo create … --source … --remote origin`).
5. Start work: `new-work <slug> <repo>:<new-branch>:<base-branch>`, or open a session at the workspace root and run `/agent-harness:orchestrate`.

## Configuration

| Variable | Required | Meaning |
|---|---|---|
| `AGENT_WORKSPACE_ROOT` | yes | Absolute path of the workspace root. If unset, the hook does nothing and the work scripts stop with an error (`workspace-init` takes the path as an argument instead). |

Set it where both hooks and tool calls see it, e.g. in `~/.claude/settings.json`:

```json
{ "env": { "AGENT_WORKSPACE_ROOT": "/home/me/workspace" } }
```

## Workspace layout

```
$AGENT_WORKSPACE_ROOT/
├─ AGENTS.md          shared rules (created from templates/AGENTS.md; the skills refer to its "work와 기록" section)
├─ repository/<repo>  source clones; worktrees are created from these
├─ work/              tasks in progress (work/orchestrator.md for the root orchestrator)
├─ arxiv/<YYYY-MM>/   archived tasks (docs only)
└─ log/YYYY-MM-DD.md  daily orchestrator log
```

## Requirements

`bash`, `git`, `python3`. Optional: `gh` (PR lookup when archiving), `graft` (for `graft-here`; override with `GRAFT_BIN`). Works on macOS and Linux.
