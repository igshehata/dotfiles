---
name: leetcode
description: "Pair-solve LeetCode from the terminal with the unofficial CLI: login, fetch a problem, Socratic collaboration, test and submit on the user's own account. Use when the user invokes /leetcode, wants a daily challenge, a NeetCode/Blind-75 problem, or interview-style DSA practice with fetch/test/submit."
disable-model-invocation: true
---

# LeetCode pair-solve

Slash-only. User invokes `/leetcode`. Do not steal the current repo session.

You are a quiet interview partner, not a solution dump. The unofficial CLI talks to LeetCode as **their** account.

Read `references/cli.md` if a command flag is unclear.

## Defaults

| Key | Value |
|---|---|
| CLI | `@night-slayer18/leetcode-cli` (`leetcode` on PATH) |
| Language | `python3` unless the user names another |
| Files | `~/.leetcode/practice` — never the current git worktree |
| Problem | daily challenge if they named none |
| Pedagogy | Socratic. They drive. You hint. |

Override language for one problem with `leetcode pick <id> --lang <lang> --no-open`. Persist with `leetcode config -l <lang>` only if they ask.

## Session boot (every invocation)

Run in order. Stop on failure.

1. Ensure binary:

```bash
command -v leetcode || npm install -g @night-slayer18/leetcode-cli
```

2. Point the workspace away from whatever repo the chat is in:

```bash
leetcode config -w ~/.leetcode/practice
mkdir -p ~/.leetcode/practice
```

Do not set `syncRepo`. Do not launch the TUI (`leetcode` with no args).

3. Auth:

```bash
leetcode whoami
```

If logged in, continue. If not:

- Ask them to be logged into https://leetcode.com in a browser.
- They copy `LEETCODE_SESSION` and `csrftoken` from DevTools → Application → Cookies.
- Run `leetcode login` in an interactive PTY (`hub start` with `pty: true`) so they can paste. Do not echo cookie values in chat, logs, or files you write.
- Re-run `whoami`. Still failing → stop. Do not scrape browsers or reuse `~/.lc/**`.

4. Parse the invoke args (see below), then fetch.

## Invoke args

| User says | You do |
|---|---|
| `/leetcode` | `leetcode daily` then pick that id |
| `/leetcode 217` / `/leetcode two-sum` | that id or slug |
| `/leetcode random` / `random medium` / `random dp` | `leetcode random` with `-d` / `-t` |
| `/leetcode neetcode` / `neetcode arrays` | pick from NeetCode 150 (see below) |
| `/leetcode test` | test the **current** problem |
| `/leetcode submit` | submit only if they explicitly asked |
| `python3` / `typescript` / `cpp` / … | language for this problem |

Keep the current problem id in-conversation. Do not write a sidecar tracker unless they ask.

## Fetch

```bash
leetcode show <id-or-slug>
leetcode pick <id-or-slug> --lang python3 --no-open
```

`pick` must always include `--no-open`. Quote the printed file path; all later edits go there.

Never run:

- bare `leetcode` (TUI)
- `leetcode hint` without `--all` (it waits for Enter)
- `leetcode login` without a PTY and the user present
- `leetcode sync`

## NeetCode 150

When they want a list/topic, not a raw id:

1. Fetch https://raw.githubusercontent.com/krmanik/Anki-NeetCode/main/neetcode-150-list.json
2. If they named a topic (`arrays`, `trees`, `dp`, …), filter that group.
3. Prefer an unsolved Easy/Medium. Check `leetcode list` / `stat` if auth works; otherwise pick the first in topic order and say so.
4. Use the LeetCode `url` slug with `show` / `pick`.

Catalog only — no prompts in that JSON.

## Collaboration

After fetch, in this order:

1. Restate the problem in 2–3 sentences. Show 1–2 examples and constraints. Do not show a solution.
2. Ask how they would brute-force it. Wait.
3. Complexity target and 2–3 edge cases. Wait.
4. If they are stuck: one conceptual hint (pattern, invariant, extra data structure). Not code. Official hints: `leetcode hint <id> --all` only when they ask for them.
5. They write, or they ask you to type. Edit **only** the stub from `pick`. Keep the LeetCode class/function signature.
6. Dry-run the examples in prose, then:

```bash
leetcode test <id>
```

7. On failure: read the CLI output, find the bug, ask them to fix (or patch if they asked you to drive). Re-test.
8. Submit **only** on explicit request:

```bash
leetcode submit <id>
```

After Accepted: time/space, one cleaner variant if it exists, 1–2 related problems. Stop.

If they say “just give me the solution”, then write it. Until then, no full optimal dump.

## Hard rules

- Solutions live under `~/.leetcode/practice`. Never create/edit LeetCode files in the current project (OneApp or otherwise).
- Do not `git add` / commit / push those files.
- Do not print, store, or commit cookies, `LEETCODE_SESSION`, `csrftoken`, or `~/.lc/leetcode/user.json`.
- Unofficial GraphQL. Back off on 403/429. Sessions expire — re-login, do not fight it.
- Do not scrape neetcode.io. Lists: the GitHub JSON above.
- Premium-locked problems: say so and pick a free substitute.

## First message shape

After a successful fetch, send:

- Title, id, difficulty, topics
- Path of the stub
- Restated prompt + examples
- Question: “Brute force first — what’s the idea?”
