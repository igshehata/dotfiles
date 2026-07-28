---
description: Analyze a Figma design against a user story for gaps and contradictions
agent: analyze
---

Analyze the Figma design against the provided user story or acceptance criteria to find contradictions, missing UI states, edge cases, and ambiguities.

Parse the Figma URL from `$ARGUMENTS`. If no URL is provided, ask the user for one.

The user story or business context should be provided in the prompt alongside the URL.

Then:

- Get screenshots of all referenced screens/nodes
- Get design context for structure and annotations
- Compare each acceptance criterion against what the design shows
- Flag missing states, contradictions, edge cases, and ambiguities
- Output a structured report suitable for a meeting agenda

Examples:

- `/analyze https://figma.com/design/abc123/MyFile?node-id=1-2`
- `/analyze https://figma.com/design/abc123/MyFile?node-id=1-2` (with story pasted in prompt)
- `/analyze` (asks for URL interactively)
