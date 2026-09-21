# leetcode CLI (night-slayer)

Package: `@night-slayer18/leetcode-cli`  
Docs: https://night-slayer18.github.io/leetcode-cli/

Agent-safe commands only. Anything interactive is marked.

## Auth

| Command | Notes |
|---|---|
| `leetcode whoami` | Check session |
| `leetcode login` | **Interactive PTY.** User pastes `LEETCODE_SESSION` + `csrftoken`. Never log values. |
| `leetcode logout` | Only if they ask |

Env override (read-only, do not persist into files): `LEETCODE_SESSION`, `LEETCODE_CSRF_TOKEN`.

## Config

```bash
leetcode config
leetcode config -l python3
leetcode config -w ~/.leetcode/practice
leetcode config -s leetcode.com
```

Stored per workspace under `~/.leetcode/workspaces/<name>/config.json`. Credentials in keychain (default), not the repo.

## Problems

| Command | Agent use |
|---|---|
| `leetcode daily` | Today's challenge |
| `leetcode show <id\|slug>` | Prompt, examples, constraints |
| `leetcode pick <id\|slug> --lang python3 --no-open` | Stub file. **Always `--no-open`.** |
| `leetcode list -d medium -s "binary tree"` | Search |
| `leetcode random -d medium -t dp` | Random |
| `leetcode hint <id> --all` | Official hints. Never bare `hint` (waits for Enter). |

## Run

| Command | Agent use |
|---|---|
| `leetcode test <id\|file>` | Sample cases |
| `leetcode test <id> -c '<input>\n<more>'` | Custom case |
| `leetcode submit <id\|file>` | Real judge. Explicit ask only. |
| `leetcode submissions <id>` | History |
| `leetcode stat` | Progress |

## Forbidden

- `leetcode` (no args) — TUI
- `leetcode hint` without `--all`
- `leetcode sync`
- `leetcode collab`, `leetcode timer` unless they asked and you can drive a PTY
