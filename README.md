# agent-harness

A Claude Code plugin (and its own marketplace) for running agent sessions inside a shared workspace:

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

## Configuration

| Variable | Required | Meaning |
|---|---|---|
| `AGENT_WORKSPACE_ROOT` | yes | Absolute path of the workspace root. If unset, the hook does nothing and the work scripts stop with an error. |

Set it where both hooks and tool calls see it, e.g. in `~/.claude/settings.json`:

```json
{ "env": { "AGENT_WORKSPACE_ROOT": "/home/me/workspace" } }
```

## Workspace layout

```
$AGENT_WORKSPACE_ROOT/
├─ AGENTS.md          shared rules (not shipped; the skills refer to its "work와 기록" section)
├─ repository/<repo>  source clones; worktrees are created from these
├─ work/              tasks in progress (work/orchestrator.md for the root orchestrator)
├─ arxiv/<YYYY-MM>/   archived tasks (docs only)
└─ log/YYYY-MM-DD.md  daily orchestrator log
```

## Requirements

`bash`, `git`, `python3`. Optional: `gh` (PR lookup when archiving), `graft` (for `graft-here`; override with `GRAFT_BIN`). Works on macOS and Linux.
