# Memory Bank Reading Guide

## Purpose

The memory-bank provides **business context** that technical linting cannot detect. This guide explains how to read and apply memory-bank content during code review.

## Why Memory-Bank Matters for Review

| What Technical Review Catches | What Memory-Bank Review Catches |
|------------------------------|--------------------------------|
| Unused variables | Incorrect business logic |
| Type errors | Missing edge cases |
| Performance anti-patterns | Wrong user flow |
| Security vulnerabilities | Domain rule violations |
| Code style issues | Integration contract breaks |

**Example:** A top-up feature might pass all technical checks but violate the business rule that top-up amount must be rounded to nearest R5.

## Reading Order

**Always read in this order (skip if file doesn't exist):**

### 1. `.clinerules/MemoryBank.md`

- Understanding of how memory-bank is structured
- Gives context on file relationships

### 2. `memory-bank/projectbrief.md`

- Foundation document
- Core requirements and goals
- Project scope boundaries
- **Review focus:** Are changes within scope?

### 3. `memory-bank/productContext.md`

- Why the project exists
- Problems it solves
- User experience goals
- **Review focus:** Does the change improve or harm UX?

### 4. `memory-bank/systemPatterns.md`

- System architecture
- Design patterns in use
- Component relationships
- Critical implementation paths
- **Review focus:** Does the change follow established patterns?

### 5. `memory-bank/techContext.md`

- Technologies used
- Development constraints
- Dependencies
- **Review focus:** Are correct tools/libraries being used?

### 6. `memory-bank/activeContext.md`

- Current work focus
- Recent changes and decisions
- Active considerations
- **Review focus:** Is this change aligned with current priorities?

### 7. `memory-bank/progress.md`

- What works / what's broken
- Known issues
- **Review focus:** Does change address known issues? Does it introduce regression?

## Mandatory + Feature-Specific Context

After reading core files, always read auth and architecture context, then match changed files to journey documentation.

### Mandatory for Every Review

- Auth docs: `memory-bank/docs/auth-*.md`, `memory-bank/docs/auth*.md`
- Architecture docs: `memory-bank/systemPatterns.md` and `memory-bank/docs/architecture*.md` (when present)

### Journey File Path Matching

```
Changed File Path              → Memory-Bank Doc
────────────────────────────────────────────────
**/topup/**, **/top-up/**      → docs/top-up.md
**/auth/**, **/login/**        → docs/auth-and-secure-bridge.md
**/bundle/**                   → docs/buy-bundle.md
**/highlight/**                → docs/highlights.md
**/homepage/**, **/home/**     → docs/homepage.md
**/contact/**                  → docs/pick-contact.md
**/product/**, **/service/**   → docs/products-and-services.md
**/my-vodacom/**, **/profile/**→ docs/my-vodacom.md
```

### Reading Feature Docs

When reading feature documentation, extract:

1. **Business Rules**
   - Validation requirements
   - Allowed/disallowed operations
   - Amount limits, format requirements
   - Required fields

2. **User Flows**
   - Expected navigation paths
   - Success/error states
   - Loading states
   - Edge case handling

3. **Integration Points**
   - API contracts
   - Event triggers
   - Analytics requirements
   - Error mapping

4. **Known Issues**
   - Existing bugs
   - Workarounds in place
   - Technical debt

## Applying Context to Review

### Business Logic Checks

For each changed file, ask:

1. **Validation:** Does it validate inputs per business rules?
2. **State Management:** Does it handle all documented states?
3. **Error Handling:** Does it map errors correctly?
4. **User Flow:** Does it preserve expected navigation?
5. **Edge Cases:** Does it handle documented edge cases?

### Example Review with Context

**Context from `docs/top-up.md`:**

```markdown
- Top-up amounts must be multiples of R5
- Minimum: R5, Maximum: R1000
- User must confirm before submission
- Show loading state during API call
```

**Reviewing `TopupForm.tsx`:**

```tsx
// ❌ Missing R5 multiple validation
const handleAmountChange = (value: string) => {
  const amount = parseInt(value);
  if (amount >= 5 && amount <= 1000) {
    setAmount(amount);
  }
};

// ✅ Should be:
const handleAmountChange = (value: string) => {
  const amount = parseInt(value);
  const roundedAmount = Math.round(amount / 5) * 5;
  if (roundedAmount >= 5 && roundedAmount <= 1000) {
    setAmount(roundedAmount);
  }
};
```

### Integration Contract Checks

**From `docs/auth-and-secure-bridge.md`:**

```markdown
- All authenticated requests must include `x-session-token` header
- Token refresh happens automatically via interceptor
- On 401, redirect to login (don't retry)
```

**Review any API call changes for:**

- Correct header usage
- Proper error handling for 401
- No manual token refresh logic

## When Memory-Bank Is Missing

If `memory-bank/` directory doesn't exist:

```
"Warning: No memory-bank directory found.

Business logic validation will be limited to:
- Code patterns and conventions
- Technical best practices
- Security concerns

To enable business logic review, create memory-bank with:
- projectbrief.md
- productContext.md
- systemPatterns.md
- techContext.md
- activeContext.md
- progress.md

Continuing with technical review only."
```

## Red Flags to Watch For

Based on common memory-bank patterns:

1. **Hardcoded values** that should come from config
2. **Missing analytics** for user interactions
3. **Incorrect error messages** that don't match UX specs
4. **State that doesn't persist** when it should
5. **API calls without loading states**
6. **Missing confirmation dialogs** for destructive actions
7. **Incorrect routing** after operations
8. **Missing accessibility** attributes
