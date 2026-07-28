---
description: Visually validate a rendered page against a Figma design
agent: validate
---

Compare a rendered page against a Figma design reference for pixel-perfect accuracy.

Parse the Figma URL and optional page URL from `$ARGUMENTS`. If no Figma URL is provided, ask for one. If no page URL is provided, auto-detect from the running dev server.

Then:

- Screenshot the Figma design node as reference
- Screenshot the rendered page via agent-browser
- Compare layout, typography, colors, components, spacing
- Report: PASS or FAIL with specific differences listed

Examples:

- `/validate https://figma.com/design/abc123/MyFile?node-id=1-2 http://localhost:3000/feature`
- `/validate https://figma.com/design/abc123/MyFile?node-id=1-2` (auto-detect page URL)
- `/validate` (asks for both URLs interactively)
