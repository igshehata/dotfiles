---
name: code-review
description: Local branch code review with silent modifications. Loads memory-bank for business logic context, applies React/Next.js best practices for technical patterns. Uses staged/unstaged separation - PR changes staged, agent improvements unstaged. Invoked as /code-review <feature-branch> <target-branch>
---

# Code Review Skill

## Overview

Comprehensive local code review combining:
1. **Business logic validation** via memory-bank context (domain rules, edge cases)
2. **Technical best practices** via vercel-react-best-practices (for React/Next.js)
3. **Silent code modifications** visible through `git diff`
4. **Clear staged/unstaged separation** for reviewing PR changes vs agent improvements

## Invocation

```bash
/code-review <feature-branch> <target-branch>
```

**Examples:**
```bash
/code-review feat/awesome-feature develop
/code-review fix/login-bug main
/code-review feat/topup-redesign develop
```

**Arguments:**
- `<feature-branch>` - The branch containing changes to review
- `<target-branch>` - The base branch (usually `develop` or `main`)

## Workflow

### Phase 0: Pre-flight Checks

**MUST complete before proceeding:**

1. **Verify git repository:**
   ```bash
   git rev-parse --is-inside-work-tree
   ```
   If not a git repo: Exit with "Not a git repository. Navigate to a git project first."

2. **Store original state:**
   ```bash
   ORIGINAL_BRANCH=$(git branch --show-current)
   ```

3. **Check for uncommitted changes:**
   ```bash
   git status --porcelain
   ```
   If dirty:
   ```
   "Working directory has uncommitted changes.

   Options:
   1. Stash changes and continue (--stash)
   2. Abort review

   Which option?"
   ```
   If user chooses stash: `git stash push -m "review-skill-stash"`

4. **Fetch and validate branches exist:**
   ```bash
   git fetch -p origin
   git rev-parse --verify origin/<target-branch>
   git rev-parse --verify origin/<feature-branch>
   ```
   If branch not found: Show similar branches with `git branch -a | grep -i <partial>`

   **For local-only branches:** If remote doesn't exist but local does, use local branch.

5. **Check if feature branch is already merged into target:** ⚠️ CRITICAL
   ```bash
   git merge-base --is-ancestor origin/<feature-branch> origin/<target-branch>
   ```
   If exit code is 0 (branch IS ancestor = already merged):
   ```
   "❌ Cannot review: Branch '<feature-branch>' has already been merged into '<target-branch>'.

   The feature branch commits are already part of the target branch.
   There are no changes to review.

   If you want to review a different branch, specify a branch that hasn't been merged yet."
   ```
   **EXIT immediately - do not proceed with review.**

6. **Check for actual changes between branches:**
   ```bash
   git rev-list --count origin/<target-branch>..origin/<feature-branch>
   ```
   If count is 0:
   ```
   "❌ Cannot review: No commits found between '<target-branch>' and '<feature-branch>'.

   Possible reasons:
   - Branch was already merged
   - Branch is identical to target
   - Branch needs to be rebased onto target

   Please verify the branch names and try again."
   ```
   **EXIT immediately - do not proceed with review.**

7. **Check if target branch is up to date with remote:**
   ```bash
   git fetch origin <target-branch>
   git rev-list --count <target-branch>..origin/<target-branch>
   ```
   If count > 0 (local is behind remote):
   ```
   "⚠️ Your local '<target-branch>' is behind origin/<target-branch> by N commits.

   Please update your target branch first:
     git checkout <target-branch> && git pull origin <target-branch>

   Then re-run the review:
     /code-review <feature-branch> <target-branch>
   "
   ```
   **EXIT immediately - do not proceed with review.**

8. **Compute PR fork-point (merge-base) and use it as review baseline:**
   ```bash
   MERGE_BASE=$(git merge-base origin/<feature-branch> origin/<target-branch>)
   ```
   This is mandatory. The review must always be based on `MERGE_BASE`, not `origin/<target-branch>`, so unrebased branches still show only PR commits/files.

### Phase 1: Branch Setup

**Goal:** Stage PR changes, leave agent modifications unstaged.

```bash
# Checkout feature branch
git checkout <feature-branch>

# Soft reset to PR merge-base - stages only PR changes
MERGE_BASE=$(git merge-base origin/<feature-branch> origin/<target-branch>)
git reset --soft "$MERGE_BASE"
```

**Verify changes exist:**
```bash
git diff --cached --stat
```
If no staged changes:
```
"❌ No changes found after reset.

This typically means:
- The feature branch has already been merged into the target branch
- The branches are identical
- The branch was rebased and force-pushed after merge

Please verify:
1. The feature branch hasn't been merged yet
2. You're using the correct branch names

To check merge status:
  git branch --contains <feature-branch> | grep <target-branch>

If the target branch is listed, the feature branch has been merged."
```
**EXIT immediately - do not proceed with review.**

**Result after this phase:**
- `git diff --cached` = Only PR changes since fork-point (staged)
- `git diff` = Empty (nothing unstaged yet)
- Agent modifications will appear as unstaged changes

### Phase 2: Context Loading (MANDATORY + CONDITIONAL)

This phase is staged-diff-driven. Always inspect staged PR files first, then load only required context.

1. **Get list of staged files (primary signal):**
   ```bash
   git diff --cached --name-only
   ```

2. **Load `memory-bank` skill (required):**
   - Use the `memory-bank` skill to load the core memory-bank context.

3. **Load mandatory business context (required for every review):**
   - Auth docs: `memory-bank/docs/auth-*.md`, `memory-bank/docs/auth*.md`
   - Architecture docs: `memory-bank/systemPatterns.md` plus architecture docs when present (`memory-bank/docs/architecture*.md`, `memory-bank/docs/*architecture*.md`)

4. **Load conditional journey docs (based on staged file paths):**

   | Staged File Pattern | Journey Docs to Load |
   |---------------------|----------------------|
   | `**/topup/**`, `**/top-up/**` | `memory-bank/docs/top-up.md` |
   | `**/bundle/**`, `**/buy-bundle/**` | `memory-bank/docs/buy-bundle.md` |
   | `**/highlight/**` | `memory-bank/docs/highlights.md` |
   | `**/homepage/**`, `**/home/**` | `memory-bank/docs/homepage.md` |
   | `**/contact/**`, `**/pick-contact/**` | `memory-bank/docs/pick-contact.md` |
   | `**/product/**`, `**/service/**` | `memory-bank/docs/products-and-services.md` |
   | `**/my-vodacom/**`, `**/profile/**` | `memory-bank/docs/my-vodacom.md` |

5. **Context budget rules:**
   - Always load: core memory-bank + auth + architecture.
   - Load only journeys touched by staged files.
   - Do not load unrelated journey docs.

6. **If memory-bank directory doesn't exist:**
```
"Warning: No memory-bank directory found. Business logic validation will be limited.
Continuing with technical review only."
```

### Phase 3: Tech Stack Detection

**Analyze staged files to determine which best practices to apply.**

1. **Get file extensions:**
   ```bash
   git diff --cached --name-only | sed 's/.*\.//' | sort | uniq -c | sort -rn
   ```

2. **Detection rules:**

   | Files/Patterns | Tech Stack | Best Practices Source |
   |---------------|------------|----------------------|
   | `*.tsx`, `*.jsx`, `next.config.*`, `app/**/*.ts` | React/Next.js | `vercel-react-best-practices` skill |
   | `*.py`, `pyproject.toml`, `requirements.txt` | Python | Search via `npx skills find python` |
   | `*.go`, `go.mod` | Go | Search via `npx skills find golang` |
   | `*.rs`, `Cargo.toml` | Rust | Search via `npx skills find rust` |

3. **Check memory-bank/techContext.md for project-specific patterns:**
   - OneDS component usage patterns
   - Error handling conventions
   - Logging requirements
   - API integration patterns

### Phase 4: Best Practices Loading

**If React/Next.js detected (most common for this project):**

Load the `vercel-react-best-practices` skill and apply rules by priority:

**CRITICAL Priority (must fix):**
- Waterfall elimination (defer await, parallel fetching)
- Bundle size (avoid barrel imports, dynamic imports for heavy components)
- Rendering optimization (prevent layout shifts, streaming)

**HIGH Priority (should fix):**
- Data fetching patterns (cache, revalidation)
- Image optimization (next/image, proper sizing)
- Client/server boundary (minimize 'use client')

**MEDIUM Priority (nice to fix):**
- Error boundaries
- Proper Suspense usage
- Form handling patterns

**LOW Priority (mention but don't auto-fix):**
- Minor optimizations
- Style preferences

**Project-specific rules from memory-bank:**
- OneDS component patterns (from systemPatterns.md)
- Error mapping pipeline (from techContext.md)
- Analytics patterns (from common-patterns.md if exists)

### Phase 5: Review & Modification

**For each staged file:**

1. **Get full diff:**
   ```bash
   git diff --cached -- <file-path>
   ```

2. **Read full file content:**
   Use Read tool to get complete context, not just changed lines.

3. **Business Logic Review (from memory-bank context):**
   - Does the change follow documented business rules?
   - Are edge cases handled as specified?
   - Does error handling match expected behavior?
   - Are user flows preserved correctly?
   - Missing validation based on domain knowledge?

4. **Technical Review (from best practices):**
   - For React/Next.js: Apply vercel-react-best-practices rules
   - Check for anti-patterns specific to the tech stack
   - Performance implications
   - Type safety issues
   - Security concerns

5. **Structural Pattern Conformance (mandatory):**
   - For App Router server features, validate that `data.ts` owns:
     - server fetching (`auth`, CMS/API calls)
     - translation shaping (`ctr`, translation key mapping)
     - feature-flag resolution
     - page-level view model assembly (`getPageData`, `getContext`)
   - `page.tsx`/`layout.tsx` should primarily orchestrate render and pass props.
   - Flag as a pattern violation when `page.tsx` contains substantial translation shaping (many `ctr(...)` calls) or data composition that belongs in `data.ts`.
   - Use existing features as references before flagging: `src/app/top-up/**/data.ts`, `src/app/products-and-services/data.ts`, `src/app/buy-bundle/**/data.ts`.
   - Severity guidance:
     - `HIGH`: violation causes duplicated logic across routes or inconsistent behavior
     - `MEDIUM`: violation increases maintenance/test cost but behavior is still correct
     - `LOW`: minor placement inconsistency without practical impact

6. **Identify issues by severity:**
   ```
   CRITICAL - Must fix before merge (bugs, security, breaking changes)
   HIGH     - Should fix (performance, anti-patterns)
   MEDIUM   - Recommended (code quality, maintainability)
   LOW      - Optional (style, minor improvements)
   ```

7. **Make silent modifications:**
   - Use Edit tool to fix issues
   - DO NOT add inline comments explaining changes
   - All modifications appear as unstaged changes
   - User views improvements via `git diff`

### Phase 6: Summary & Cleanup

**Output structured summary:**

```markdown
## Code Review Summary

**Branch:** `<feature-branch>` → `<target-branch>`
**Files Reviewed:** N

### Context Loaded
- [x] projectbrief.md
- [x] productContext.md
- [x] systemPatterns.md
- [x] techContext.md
- [x] Mandatory docs: auth + architecture
- [x] Journey docs (conditional): top-up.md
- [x] vercel-react-best-practices (if React/Next.js detected)

### Issues Found

| File | Severity | Issue | Resolution |
|------|----------|-------|------------|
| src/features/topup/TopupForm.tsx | CRITICAL | Missing validation | Added null check |
| src/hooks/useTopup.ts | HIGH | Sequential fetches | Parallelized with Promise.all |
| ... | ... | ... | ... |

### Improvements Applied

View all improvements with:
```bash
git diff
```

### Verification Commands

```bash
# View staged (original PR changes)
git diff --cached

# View unstaged (agent improvements)
git diff

# If satisfied, stage improvements
git add -A

# Restore to original state
git checkout <original-branch>
git stash pop  # if stashed
```

### Restore Command

To abort and return to original state:
```bash
git checkout -f <original-branch>
```
```

## Error Handling

| Scenario | Response |
|----------|----------|
| Not a git repo | Exit with instructions to navigate to git project |
| Dirty working directory | Offer stash/abort options |
| Branch doesn't exist | Show similar branches, ask for correction |
| **Branch already merged** | **EXIT - Cannot review merged branch** |
| **No commits between branches** | **EXIT - Nothing to review** |
| **Target branch behind remote** | **EXIT - Ask user to pull target branch first** |
| Feature branch not rebased onto target | Handled automatically by merge-base baseline; continue review |
| memory-bank missing | Warn and continue with technical review only |
| Best practices skill missing | Warn and continue with memory-bank review only |
| Network error on fetch | Retry once, then use local branches |
| Merge conflicts during reset | Abort with instructions to resolve manually |
| No staged changes after reset | EXIT - Branch likely already merged or identical |

## Files Reference

Supporting files in `~/.config/opencode/skills/code-review/references/`:

- `memory-bank-guide.md` - Detailed memory-bank reading workflow
- `tech-detection.md` - File extension to tech stack mapping
- `review-checklist.md` - Technical and business review patterns

## Key Principles

1. **Business + Technical**: Both memory-bank context AND technical best practices are required for thorough review
2. **Silent Modifications**: Fix issues directly, don't add comments - changes visible via `git diff`
3. **Staged/Unstaged Separation**: Clear distinction between PR code and agent improvements
4. **Context-Aware**: Always load auth + architecture, then load journey docs based on changed files
5. **Severity-Based**: Prioritize CRITICAL > HIGH > MEDIUM > LOW
6. **Context Budgeting**: Always load core + auth + architecture, journeys only when touched
7. **Restorable**: Always provide commands to return to original state
