---
description: Review the current worktree or an explicit branch against develop or another target
agent: review
---

Run the shared review workflow.

Start by calling `review_context` with `rawArguments` set to `$ARGUMENTS`.

Then:

- trust the tool output for normalized branches, mode, and requested features
- abort immediately if the tool reports invalid review setup
- call `review_worktree` with the tool's `mode`, `reviewBranch`, `reviewRef`, and `activeWorktree`
- review only inside the returned `reviewPath`
- load `project-context`
- load `code-reviewer`
- load `vercel-react-best-practices` only when the tool indicates frontend or React or Next relevance
- produce a structured review report with findings and evidence

Examples:

- `/review`
- `/review feat/my-branch`
- `/review feat/my-branch develop`
- `/review target=main`
- `/review branch=feat/my-branch target=develop features=buy-bundle,topup`
