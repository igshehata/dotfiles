---
description: Review changed files or the full main/develop project tree
agent: review
---

Run the shared review workflow.

Start by calling `review_context` with `rawArguments` set to `$ARGUMENTS`.

Then:

- trust the tool output for normalized branches, worktree mode, review scope, and files
- abort immediately if the tool reports invalid review setup
- call `git_worktree` with the tool's `mode`, `branch`, `ref`, and `activeWorktree`
- review only inside the returned `path`
- load `code-reviewer`
- load `vercel-react-best-practices` only when the tool indicates frontend or React or Next relevance
- produce a structured review report with findings and evidence

`main` and `develop` are full-project review branches. When either is the effective review branch, review the complete repository tree even when `changedFiles` is empty; any supplied target is normalized to that branch.

Examples:

- `/review`
- `/review feat/my-branch`
- `/review feat/my-branch develop`
- `/review target=main`
- `/review branch=feat/my-branch target=develop`
- `/review main`
- `/review develop`
- `/review main target=main`
