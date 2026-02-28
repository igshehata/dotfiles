# Code Review Checklist

## Purpose

Comprehensive checklist combining business logic and technical review patterns.

## Severity Levels

| Level | Description | Action |
|-------|-------------|--------|
| CRITICAL | Bugs, security issues, breaking changes | Must fix before merge |
| HIGH | Performance, anti-patterns, data issues | Should fix |
| MEDIUM | Code quality, maintainability | Recommended fix |
| LOW | Style, minor improvements | Optional, mention only |

---

## Business Logic Review

### Domain Rules

- [ ] **Validation matches business requirements**
  - Amount limits, format requirements
  - Required vs optional fields
  - Allowed values/enums

- [ ] **Business rules enforced**
  - Calculations correct (rounding, percentages)
  - Conditional logic matches specs
  - State transitions valid

- [ ] **Edge cases handled**
  - Empty/null values
  - Boundary conditions (min/max)
  - Concurrent operations

### User Experience

- [ ] **User flow preserved**
  - Navigation paths correct
  - Back button behavior
  - Deep linking works

- [ ] **States handled correctly**
  - Loading states shown
  - Error states displayed
  - Empty states handled
  - Success feedback provided

- [ ] **Confirmation dialogs present**
  - Destructive actions
  - Irreversible operations
  - Payment confirmations

### Integration Contracts

- [ ] **API contracts followed**
  - Request format correct
  - Response handling complete
  - Headers included

- [ ] **Error mapping correct**
  - API errors mapped to user messages
  - Error codes handled
  - Retry logic appropriate

- [ ] **Analytics events fired**
  - User interactions tracked
  - Conversion events logged
  - Error events captured

---

## Technical Review (React/Next.js)

### CRITICAL - Waterfalls

- [ ] **No sequential awaits when parallel possible**
  ```tsx
  // ❌ Sequential
  const user = await getUser();
  const posts = await getPosts();

  // ✅ Parallel
  const [user, posts] = await Promise.all([getUser(), getPosts()]);
  ```

- [ ] **Defer await until needed**
  ```tsx
  // ❌ Blocking
  const data = await fetchData();
  return <Component data={data} />;

  // ✅ Streaming
  const dataPromise = fetchData();
  return <Suspense><Component dataPromise={dataPromise} /></Suspense>;
  ```

- [ ] **No waterfall chains in API routes**

### CRITICAL - Bundle Size

- [ ] **No barrel file imports**
  ```tsx
  // ❌ Barrel import
  import { Button } from '@/components';

  // ✅ Direct import
  import { Button } from '@/components/Button';
  ```

- [ ] **Heavy components dynamically imported**
  ```tsx
  // ❌ Static import
  import { Chart } from 'heavy-chart-lib';

  // ✅ Dynamic import
  const Chart = dynamic(() => import('heavy-chart-lib'), { ssr: false });
  ```

- [ ] **Conditional module loading**
  ```tsx
  // ❌ Always load
  import { analytics } from 'analytics';

  // ✅ Load when needed
  const analytics = await import('analytics');
  ```

### HIGH - Rendering

- [ ] **Prevent layout shift**
  - Images have width/height
  - Placeholders for dynamic content
  - Skeleton loaders

- [ ] **Strategic Suspense boundaries**
  - Don't wrap everything
  - Boundaries at meaningful points
  - Fallbacks are useful

- [ ] **Minimize 'use client' surface**
  - Only what needs interactivity
  - Extract server components
  - Keep client components small

### HIGH - Data Fetching

- [ ] **Cache configuration appropriate**
  - Static data cached
  - Dynamic data revalidated
  - User-specific data not cached

- [ ] **Revalidation strategy correct**
  - Time-based for stale-ok data
  - On-demand for real-time data

- [ ] **Error boundaries present**
  - API failures handled
  - Graceful degradation

### MEDIUM - Images

- [ ] **Using next/image**
  - Not raw `<img>` tags
  - Proper sizing props
  - Priority for LCP images

- [ ] **Responsive images**
  - `sizes` prop for responsive
  - Appropriate quality settings

### MEDIUM - Forms

- [ ] **Progressive enhancement**
  - Works without JS where possible
  - Server actions for forms

- [ ] **Optimistic updates**
  - useOptimistic for instant feedback
  - Rollback on error

---

## Technical Review (General)

### Security

- [ ] **No hardcoded secrets**
  - API keys
  - Credentials
  - Tokens

- [ ] **Input sanitization**
  - User input escaped
  - SQL injection prevented
  - XSS prevented

- [ ] **Authentication checked**
  - Protected routes guarded
  - Tokens validated
  - Session handling correct

### Type Safety

- [ ] **No `any` types without justification**
- [ ] **Proper null checks**
- [ ] **Exhaustive switch statements**
- [ ] **Generic types where appropriate**

### Error Handling

- [ ] **Errors caught and handled**
- [ ] **User-friendly error messages**
- [ ] **Logging for debugging**
- [ ] **No silent failures**

### Performance

- [ ] **No memory leaks**
  - Event listeners cleaned up
  - Subscriptions unsubscribed
  - Timers cleared

- [ ] **Efficient re-renders**
  - useMemo/useCallback appropriate
  - React.memo for pure components
  - Keys on list items

- [ ] **Lazy loading**
  - Heavy components
  - Below-fold content
  - Non-critical features

### Code Quality

- [ ] **Consistent naming**
- [ ] **Functions do one thing**
- [ ] **No dead code**
- [ ] **No duplicate logic**

---

## Project-Specific Patterns

### OneDS Components (from systemPatterns.md)

- [ ] **Using OneDS components correctly**
  - Proper props
  - Theme integration
  - Accessibility attributes

- [ ] **Following component hierarchy**
  - Layout components
  - Feature components
  - Shared components

### Error Mapping Pipeline (from techContext.md)

- [ ] **API errors mapped through pipeline**
- [ ] **Error codes have translations**
- [ ] **Fallback error messages exist**

### Analytics (from common-patterns.md)

- [ ] **Page views tracked**
- [ ] **User actions logged**
- [ ] **Conversion events fired**
- [ ] **Error events captured**

---

## Review Output Template

```markdown
### File: `<file-path>`

#### Issues Found

| Severity | Line | Issue | Fix |
|----------|------|-------|-----|
| CRITICAL | 45 | Sequential awaits | Parallelized |
| HIGH | 78 | Missing error boundary | Added |
| MEDIUM | 12 | Barrel import | Direct import |

#### Business Logic Notes
- Validation matches top-up.md requirements
- Missing confirmation dialog before submit (CRITICAL)

#### Technical Notes
- Good use of Suspense boundaries
- Consider extracting server component from line 30-50
```

---

## Quick Reference

### Must Check Every Review
1. Business rules from memory-bank
2. User flow preservation
3. Error handling
4. Security concerns
5. Type safety

### React/Next.js Specific
1. No waterfalls (CRITICAL)
2. Bundle size (CRITICAL)
3. Rendering optimization (HIGH)
4. Data fetching patterns (HIGH)

### Before Marking Complete
1. All CRITICAL issues fixed
2. HIGH issues fixed or documented
3. MEDIUM issues mentioned
4. Summary provided
5. Restore command included
