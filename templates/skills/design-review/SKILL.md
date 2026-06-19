---
name: design-review
description: Critique an existing UI against a design rubric and propose concrete fixes. Use when asked to review, critique, audit, or polish a UI, "does this look professional", or after a UI feature ships. The QA counterpart to the frontend-design skill.
---

# Design review

Review a UI honestly against the rubric and propose specific, prioritized fixes (apply them only
when asked). If you can open the page (a browser / Playwright MCP), screenshot the key views at
several widths first - a picture is worth 1000 tokens.

## Rubric (score each; call out the worst offenders)
- Visual hierarchy: one clear anchor per screen; scannable headlines; one primary action.
- Spacing: consistent scale (4/8px base); no cramped or sparsely-floating sections.
- Typography: sensible scale, real weight contrast, no banned default fonts (Inter/Roboto/etc.).
- Color/contrast: token-driven; meets 4.5:1 body / 3:1 large text and UI.
- Interaction states: hover / focus / active / disabled / empty / error all present.
- Dark mode: parity if the app supports it.
- Responsiveness: no overflow; sane breakpoints at 360 / 768 / 1024 / 1440.
- Accessibility: visible focus, labels, target size, color is not the only signal.
- Motion: adds hierarchy, not noise; respects prefers-reduced-motion.

## Common catches
Sparse or templated layouts, missing dark mode, missing interaction/empty/error states,
inconsistent spacing, and accessibility gaps (focus, labels, contrast).

## Output
For each issue: where it is, why it hurts, and the concrete change. Grade severity
(block / fix soon / minor) so attention goes to what matters.
