# Tech Stack Detection

## Purpose

Detect the technology stack from changed files to load appropriate best practices.

## Detection Logic

### Step 1: Analyze File Extensions

```bash
git diff --cached --name-only | sed 's/.*\.//' | sort | uniq -c | sort -rn
```

### Step 2: Match Patterns

| Files/Patterns | Tech Stack | Confidence |
|---------------|------------|------------|
| `*.tsx`, `*.jsx` | React | HIGH |
| `next.config.*`, `app/**/*.ts`, `pages/**/*.tsx` | Next.js | HIGH |
| `*.vue` | Vue.js | HIGH |
| `*.svelte` | Svelte | HIGH |
| `angular.json`, `*.component.ts` | Angular | HIGH |
| `*.py`, `pyproject.toml`, `requirements.txt` | Python | HIGH |
| `*.go`, `go.mod`, `go.sum` | Go | HIGH |
| `*.rs`, `Cargo.toml` | Rust | HIGH |
| `*.java`, `pom.xml`, `build.gradle` | Java | HIGH |
| `*.kt`, `*.kts` | Kotlin | HIGH |
| `*.swift` | Swift | HIGH |
| `*.rb`, `Gemfile` | Ruby | HIGH |
| `*.php`, `composer.json` | PHP | HIGH |

### Step 3: Check Config Files

| Config File | Indicates |
|-------------|-----------|
| `next.config.js/mjs/ts` | Next.js project |
| `vite.config.*` | Vite-based project |
| `webpack.config.*` | Webpack bundling |
| `tailwind.config.*` | Tailwind CSS |
| `tsconfig.json` | TypeScript |
| `.eslintrc.*` | ESLint rules |
| `jest.config.*` | Jest testing |
| `vitest.config.*` | Vitest testing |
| `playwright.config.*` | Playwright E2E |
| `cypress.config.*` | Cypress E2E |

## Best Practices Sources

### React/Next.js

**Primary Source:** `vercel-react-best-practices` skill

**Load condition:** Load this skill only when staged files indicate React/Next.js (`*.tsx`, `*.jsx`, `next.config.*`, `app/**`, `pages/**`).

**Key Categories:**
1. Eliminating Waterfalls (CRITICAL)
2. Bundle Size Optimization (CRITICAL)
3. Rendering Optimization (HIGH)
4. Data Fetching (HIGH)
5. Image Optimization (MEDIUM)
6. Client/Server Boundaries (MEDIUM)

**If skill not installed:**
```bash
npx skills add vercel-labs/agent-skills@vercel-react-best-practices -g -y
```

### Python

**Search for best practices:**
```bash
npx skills find python best practices
```

**Common patterns to check:**
- Type hints usage
- Exception handling
- Import organization
- Docstring format
- Virtual environment setup

### Go

**Search for best practices:**
```bash
npx skills find golang best practices
```

**Common patterns to check:**
- Error handling (no silent errors)
- Interface usage
- Goroutine/channel patterns
- Context propagation
- Dependency injection

### Rust

**Search for best practices:**
```bash
npx skills find rust best practices
```

**Common patterns to check:**
- Ownership and borrowing
- Error handling with Result
- Lifetime annotations
- Clippy lint compliance
- Unsafe usage justification

## Project-Specific Patterns

### From memory-bank/techContext.md

Read and apply:
- Project-specific libraries
- Custom patterns
- Internal conventions
- Forbidden patterns

### From memory-bank/systemPatterns.md

Read and apply:
- Architecture patterns
- Component structure
- Data flow patterns
- State management approach

## Multi-Stack Projects

When multiple tech stacks detected:

1. **Identify primary stack** (most changed files)
2. **Load primary best practices**
3. **Note secondary stacks** for context

**Example:**
```
Detected:
- React/Next.js: 15 files (PRIMARY)
- CSS/Tailwind: 8 files
- TypeScript: 23 files

Loading:
- vercel-react-best-practices (React/Next.js)
- TypeScript strict mode checks
- Tailwind class ordering
```

## Fallback Behavior

If no best practices skill found:

```
"No specific best practices skill found for <tech-stack>.

Applying general code review patterns:
- Code readability
- Error handling
- Type safety (if applicable)
- Security concerns
- Performance basics

Consider installing a best practices skill:
npx skills find <tech-stack> best practices
```

## Detection Output Format

Report detected stack in summary:

```markdown
### Tech Stack Detected

| Technology | Files Changed | Best Practices |
|------------|---------------|----------------|
| React/Next.js | 12 | vercel-react-best-practices |
| TypeScript | 12 | Built-in type checking |
| Tailwind CSS | 5 | Class ordering |

Project-specific patterns loaded from:
- memory-bank/techContext.md
- memory-bank/systemPatterns.md
```
