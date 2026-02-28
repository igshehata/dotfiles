---
name: leetcode
description: Interactive LeetCode problem solving in JavaScript with vim motion hints
---

Initiate an interactive LeetCode problem-solving session in JavaScript following this 9-step process:

1. **Load Progress**: Scan `r/leetcode.md` and all `k/LeetCode - *.md` notes to identify current progress across all topics
2. **Create Boilerplate**: Before presenting the problem, create the folder structure at `/Users/islam.shehata/personal/leetcode/`:
   - Create folder: `{problem-number}-{problem-name}/` (e.g., `217-contains-duplicate/`)
   - Create `solution.js`: Starter code with function signature, docstring, type hints
   - Create `test_solution.js`: Bun test file with all test cases (examples + edge cases)
   - Create `README.md`: Problem description and test running instructions
3. **Present Problem**: Show the next unsolved problem from the current or next topic with:
   - Problem number and name
   - Difficulty level
   - Problem description
   - Example inputs/outputs
   - Constraints
4. **User Analyzes**: Wait for the user to:
   - Identify the pattern/approach
   - Discuss time/space complexity expectations
   - Outline their solution strategy
5. **User Implements (JavaScript)**: Guide the user through implementation in JavaScript
   - **Vim Motion Hints**: Every 3-4 problems, suggest a relevant vim motion as a hint (e.g., "Try `ci(` to change inside parentheses", "Use `dd` to delete line", "Try `V` for visual line mode")
   - Encourage clean, readable code
   - Suggest writing helper functions where appropriate
6. **Review & Test**: After implementation:
   - Analyze the solution for correctness
   - Run through test cases (including edge cases)
   - Discuss actual time/space complexity
   - Suggest optimizations if applicable
7. **Discuss Pattern**: Explain:
   - The pattern/technique used
   - When to recognize this pattern in other problems
   - Common variations
   - Related problems that use the same pattern
8. **Update Progress**: Update the relevant `k/LeetCode - [Topic].md` note:
   - Mark problem as ✅ Solved
   - Fill in attempts, date solved, complexity, key insight
   - Update the topic's frontmatter properties (solved count, last-solved date)
9. **Suggest Next**: Recommend the next problem:
   - Continue in same topic if mastery not yet achieved
   - Move to new topic if current topic is complete
   - Provide rationale for the suggestion

**Session Management**:

- Track vim motions taught in the session
- Maintain encouraging, educational tone
- Focus on deep understanding over speed
- Connect patterns to real-world scenarios when possible
- Reference the user's production experience (30M users, M-Pesa) when relevant to scale/optimization discussions

**Repository Location**: All solutions are saved to `/Users/islam.shehata/personal/leetcode/`
