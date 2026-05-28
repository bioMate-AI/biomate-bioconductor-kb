# Audit Overlay — Byte-by-byte Comparison vs Reference

**Date:** 2026-05-28
**Reference:** `reference/claude_design/IND_design/ind/{Overlays.jsx, styles-ind.css}`
**Current:** `frontend/client/src/components/ind-report/IndOverlays.tsx::IndAuditOverlay`

## CSS

All 5 classes that drive the audit-overlay render are **byte-identical** to the reference:

| Class | Result |
|---|---|
| `.ind-audit-overlay` | ✅ identical (position: absolute; inset: 0; animation: slidein 0.18s ease-out) |
| `.ind-audit-head` | ✅ identical (padding, border-bottom, flex layout) |
| `.ind-audit-list` | ✅ identical (flex 1, overflow-y, padding, gap 12) |
| `.ind-audit-finding` | ✅ identical (border + per-severity left border, addressed opacity 0.6) |
| `.ind-audit-foot` | ✅ identical (padding, border-top, font-size, layout) |
| `@keyframes slidein` | ✅ identical (translateX(8px)→0, opacity 0→1) |

Slide-in animation timing, easing, distance, all unchanged from reference.

## JSX

Render tree mirrors the reference. Same class names, same inline styles, same option labels:

- `<div className="ind-audit-overlay">` outer wrapper
- `<header className="ind-audit-head">` with `<h3>Regulatory Audit</h3>` + Close button
- `<div className="ind-audit-meta">` severity counter chips + filter select
- `<div className="ind-audit-list">` per-finding cards
- Per-finding: `.ind-audit-finding-head` (section badge + severity chip + addressed indicator) + `.title` + `.desc` + `.acts` (Jump-to + Dismiss)
- Inline dismissal picker with 4 reason radios
- `<footer className="ind-audit-foot">` with chain records + last verified

## Deltas (improvements over the reference)

| Surface | Reference | Current | Verdict |
|---|---|---|---|
| Dismissal flow | "Dismiss with reason" button calls `setDismissingId(null)` — no backend POST | Calls `captureDismissal()` → `POST /api/ind-report/audit/:id/dismiss` (JSONL persistence) | ✅ Real backend wiring (P1-2) |
| Dismissal feedback | No UI change after dismiss; user has to refresh to see effect | Optimistic UI — card fades + "Dismissed" badge instantly; severity counter drops; rollback on POST failure | ✅ P1-2 improvement |
| Jump-to-section | `scrollIntoView({ block: 'start' })` (jumpy) | `scrollIntoView({ block: 'start', behavior: 'smooth' })` | ✅ Smooth-scroll (P0-2) |
| Parent mount | Reference uses a manual portal (`AuditPortalContainer` with `target.style.position = 'relative'` hack at line 270 of HTML) | Mounted via `auditOverlay` slot prop into `IndDocPanel` (the doc panel is already `position: sticky` = positioned ancestor) | ✅ Cleaner, no DOM mutation |
| Stable test selectors | Only `data-tour` (which we stripped) | `data-testid="audit-finding-${i}"` + `data-testid="audit-dismissed-badge-${i}"` | ✅ E2E-friendly |
| Type safety | Plain JSX | `AuditFindingWithMeta` + `AuditOverlayProps` types | ✅ Typed |

## Where current and reference are identical (no improvement, no regression)

- Severity filter values (`all`, `CRITICAL`, `MAJOR`, `MINOR`, `INFO`)
- Severity counter chip with `⚠ N` for non-zero or `○ 0` for zero
- 4 reason radios (na, done, accept, disag) and their labels verbatim
- Per-severity left-border colors (crit/major/minor/info → err/warn/minor/info CSS var)
- Animation timing (0.18s ease-out)
- Layout primitives (flex / grid sizing)

## Net assessment

The audit overlay matches the Claude design pixel-for-pixel on layout and animation, with **strict improvements** in:
1. backend persistence (real POST vs reference's local-only)
2. optimistic UI feedback
3. parent mounting via slot prop vs DOM-mutation portal
4. smooth-scroll on Jump-to

No regressions vs the reference. The `data-tour` attributes were intentionally stripped (P1-7) because we removed the tour port; replaced with `data-testid` for E2E test stability.
