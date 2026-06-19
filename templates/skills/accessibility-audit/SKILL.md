---
name: accessibility-audit
description: Run a focused WCAG 2.2 AA accessibility pass and remediate. Use when asked about accessibility, a11y, WCAG, screen-reader support, keyboard navigation, or color contrast. Deeper than the a11y gate inside the frontend-design skill.
---

# Accessibility audit (WCAG 2.2 AA)

Audit, then report each failure with its success-criterion number and a concrete fix.

## Steps
1. Automated pass: run axe or Lighthouse if available; note findings (but never stop there).
2. Keyboard only: tab through everything - logical order, no traps, every interactive element
   reachable, focus ALWAYS visible (>=3:1 contrast vs unfocused, outline >=2px).
3. Contrast: body text >=4.5:1; large text (>=24px, or >=18.66px bold) and UI/graphics >=3:1.
4. Semantics + ARIA: real landmarks and semantic HTML first, ARIA only to fill gaps; every input
   has a label; meaningful images have alt text; the visible label matches the accessible name.
5. Targets + pointer: interactive targets >=24x24 CSS px; any drag has a single-pointer alternative.
6. Forms: errors clearly identified with how to fix; do not require re-entering known data.
7. Motion + color: respect prefers-reduced-motion; never convey meaning by color alone.

## Definition of done
Keyboard-operable, visible focus everywhere, contrast thresholds met, labels/alt/landmarks
present, 24px targets, reduced-motion honored - each remaining gap listed with its SC number.
