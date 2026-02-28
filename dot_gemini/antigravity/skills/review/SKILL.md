---
name: review
description: Local branch code review with silent modifications. Loads memory-bank for business logic context, applies React/Next.js best practices for technical patterns. Uses staged/unstaged separation - PR changes staged, agent improvements unstaged. Invoked as /review <feature-branch> <target-branch>
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
/review <feature-branch> <target-branch>
```

**Examples:**
```bash
/review feat/awesome-feature develop
/review fix/login-bug main
/review feat/topup-redesign develop
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
     /review <feature-branch> <target-branch>
   "
   ```
   **EXIT immediately - do not proceed with review.**

8. **Check if feature branch needs rebase:**
   ```bash
   git merge-base origin/<feature-branch> origin/<target-branch>
   git rev-parse origin/<target-branch>
   ```
   If merge-base != target branch HEAD (feature branch is behind target):
   ```
   "⚠️ Feature branch '<feature-branch>' is not up to date with '<target-branch>'.

   The feature branch is based on an older version of the target branch.
   For accurate review, please rebase first:
     git checkout <feature-branch>
     git rebase origin/<target-branch>
     git push -f origin <feature-branch>

   Then re-run the review:
     /review <feature-branch> <target-branch>

   Continue anyway? (Review will compare against current target, may show extra changes)
   "
   ```
   **If user declines, EXIT. If user continues, warn in summary.**

### Phase 1: Context Loading (MANDATORY)

**CRITICAL: Read memory-bank files INLINE. DO NOT delegate to another skill.**

This phase loads business context to catch domain-specific bugs that technical linting cannot detect.

**Read in order (skip if file doesn't exist):**

1. `.clinerules/MemoryBank.md` - Understanding of memory-bank workflow
2. `memory-bank/projectbrief.md` - Project foundation, core requirements
3. `memory-bank/productContext.md` - Why it exists, UX goals, user problems solved
4. `memory-bank/systemPatterns.md` - Architecture, design patterns, component relationships
5. `memory-bank/techContext.md` - Technologies, constraints, dependencies
6. `memory-bank/activeContext.md` - Current priorities, recent decisions
7. `memory-bank/progress.md` - Known issues, what's working/broken

**Path:** Use project root to locate `memory-bank/` directory.

**If memory-bank directory doesn't exist:**
```
"Warning: No memory-bank directory found. Business logic validation will be limited.
Continuing with technical review only."
```

### Phase 2: Branch Setup

**Goal:** Stage PR changes, leave agent modifications unstaged.

```bash
# Checkout feature branch
git checkout <feature-branch>

# Soft reset to target branch - this stages all PR changes
git reset --soft origin/<target-branch>
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
- `git diff --cached` = All changes in the PR (staged)
- `git diff` = Empty (nothing unstaged yet)
- Agent modifications will appear as unstaged changes

### Phase 3: Feature-Specific Context

**After analyzing staged files, load relevant memory-bank documentation.**

1. **Get list of changed files:**
   ```bash
   git diff --cached --name-only
   ```

2. **Match files to memory-bank docs:**

   | Changed File Pattern | Memory-Bank Docs to Load |
   |---------------------|-------------------------|
   | `**/topup/**`, `**/top-up/**` | `memory-bank/docs/top-up.md` |
   | `**/auth/**`, `**/login/**` | `memory-bank/docs/auth-*.md` |
   | `**/bundle/**`, `**/buy-bundle/**` | `memory-bank/docs/buy-bundle.md` |
   | `**/highlight/**` | `memory-bank/docs/highlights.md` |
   | `**/homepage/**`, `**/home/**` | `memory-bank/docs/homepage.md` |
   | `**/contact/**`, `**/pick-contact/**` | `memory-bank/docs/pick-contact.md` |
   | `**/product/**`, `**/service/**` | `memory-bank/docs/products-and-services.md` |
   | `**/my-vodacom/**`, `**/profile/**` | `memory-bank/docs/my-vodacom.md` |

3. **Read matched documentation:**
   For each matched doc, read the full file to understand:
   - Business rules and constraints
   - Expected user flows
   - Edge cases and error handling requirements
   - Integration points

### Phase 4: Tech Stack Detection

**Analyze staged files to determine which best practices to apply.**

1. **Get file extensions:**
   ```bash
   git diff --cached --name-only | sed 's/.*\.//' | sort | uniq -c | sort -rn
   ```

2. **Detection rules:**

   | Files/Patterns | Tech Stack | Best Practices Source |
   |---------------|------------|----------------------|
   | `*.tsx`, `*.jsx`, `next.config.*`, `app/**/*.ts` | React/Next.js | `~/.claude/skills/vercel-react-best-practices/AGENTS.md` |
   | `*.py`, `pyproject.toml`, `requirements.txt` | Python | Search via `npx skills find python` |
   | `*.go`, `go.mod` | Go | Search via `npx skills find golang` |
   | `*.rs`, `Cargo.toml` | Rust | Search via `npx skills find rust` |

3. **Check memory-bank/techContext.md for project-specific patterns:**
   - OneDS component usage patterns
   - Error handling conventions
   - Logging requirements
   - API integration patterns

### Phase 5: Best Practices Loading

**If React/Next.js detected (most common for this project):**

Load `~/.claude/skills/vercel-react-best-practices/AGENTS.md` and apply rules by priority:

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

### Phase 6: Review & Modification

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

5. **Identify issues by severity:**
   ```
   CRITICAL - Must fix before merge (bugs, security, breaking changes)
   HIGH     - Should fix (performance, anti-patterns)
   MEDIUM   - Recommended (code quality, maintainability)
   LOW      - Optional (style, minor improvements)
   ```

6. **Make silent modifications:**
   - Use Edit tool to fix issues
   - DO NOT add inline comments explaining changes
   - All modifications appear as unstaged changes
   - User views improvements via `git diff`

### Phase 7: Summary & Cleanup

**Output structured summary:**

```markdown
## Code Review Summary

**Branch:** `<feature-branch>` → `<target-branch>`
**Files Reviewed:** N

### Context Loaded
- [x] projectbrief.md
- [x] productContext.md
- [x] systemPatterns.md
- [x] techContext.md (React/Next.js detected)
- [x] Feature docs: top-up.md

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
| **Feature branch needs rebase** | **WARN - Ask user to rebase or continue with warning** |
| memory-bank missing | Warn and continue with technical review only |
| Best practices skill missing | Warn and continue with memory-bank review only |
| Network error on fetch | Retry once, then use local branches |
| Merge conflicts during reset | Abort with instructions to resolve manually |
| No staged changes after reset | EXIT - Branch likely already merged or identical |

## Files Reference

Supporting files in `~/.claude/skills/review/references/`:

- `memory-bank-guide.md` - Detailed memory-bank reading workflow
- `tech-detection.md` - File extension to tech stack mapping
- `review-checklist.md` - Technical and business review patterns

## Key Principles

1. **Business + Technical**: Both memory-bank context AND technical best practices are required for thorough review
2. **Silent Modifications**: Fix issues directly, don't add comments - changes visible via `git diff`
3. **Staged/Unstaged Separation**: Clear distinction between PR code and agent improvements
4. **Context-Aware**: Load feature-specific docs based on changed files
5. **Severity-Based**: Prioritize CRITICAL > HIGH > MEDIUM > LOW
6. **Restorable**: Always provide commands to return to original state
