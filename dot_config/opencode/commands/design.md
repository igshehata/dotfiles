---
description: Translate a Figma design into production-ready code
agent: design
---

Translate the given Figma design into production-ready code using the project's design system.

Start by parsing the Figma URL from `$ARGUMENTS`. If no URL is provided, ask the user for one.

If the user included a user story or acceptance criteria in the prompt, pass that context to @analyze for gap analysis (non-blocking — proceed with implementation regardless).

Then:

- Extract `fileKey` and `nodeId` from the URL
- Get screenshot and design context from Figma
- Load the project's design-system skill (from .opencode/skills/)
- Scan the project for existing components and patterns
- Map visual elements to project components
- Generate code that matches the design pixel-perfectly
- Validate the rendered output against the Figma reference
- Report: files generated, components used, validation result, discussion items

Examples:

- `/design https://figma.com/design/abc123/MyFile?node-id=1-2`
- `/design https://figma.com/design/abc123/MyFile?node-id=45-678`
- `/design` (asks for URL interactively)
