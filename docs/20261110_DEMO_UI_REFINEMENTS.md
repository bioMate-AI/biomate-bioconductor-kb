# 2026-11-10 — Demo UI refinements (BACE1 run_code session)

Four UI issues surfaced during a live Chinese-locale demo (summarise an assay
table + plot potency vs logP via the agentic `run_code` path). Screenshots under
`~/Desktop/business/bioconductor_screenshot/UI_refinement/`.

## 1. Chinese example → English prompt (i18n gap)
**Symptom:** In a Chinese UI, clicking a demo example injects an English prompt
into the composer (`click_chineseexampl_getEnglish.png`). The example titles and
seed prompts are hardcoded English literals.
**Root cause:** `cold-start-examples.ts` (`PREPARED_EXAMPLES[].label/prompt`),
`cold-start-demo-catalog.ts` (`context`), and `cold-start-dashboard.tsx`
(`t:`/`seed:`) are English-only — zero `zh` variants.
**Fix:** localize example titles + seed prompts for the active locale.
**Status:** see commit history.

## 2. Run Code card — no copy button, no scroll
**Symptom:** `run_code_no_scrolldown_noCopyCode.png` — the code preview is
clipped ("+40 lines") with no way to scroll the full script and no copy button.
**Root cause:** `code-execution-block.tsx` expanded code rendered in a
`whitespace-pre-wrap overflow-x-auto` block with no max-height and no copy
affordance.
**Fix (done):** added a Copy button (clipboard + "Copied" feedback) and a
scrollable viewport (`whitespace-pre overflow-auto max-h-96`) to the expanded
code surface.

## 3. Claimed plot from run_code is not shown
**Symptom:** `whereIsClaimedPlotFromRunCode.png` — the response says a scatter
plot was generated (300 dpi) but no image renders in chat.
**Root cause:** `code-execution-block.tsx` renders `output_files[].preview` as
TEXT; image outputs (PNG/SVG) are never shown as `<img>`, and output files are
buried in the collapsed tool card.
**Fix:** render image output files as images and surface generated plots.
**Status:** in progress (see commit history).

## 4. "Redo as a validated run" button — removed (deferred)
**Symptom:** `whatIsThis.png` — the "🧪 作为已验证运行重做 / Redo as a validated
run" action is unclear.
**Decision (user, 2026-11-10):** remove it now. Re-running an instant `run_code`
answer "as a validated run" cannot faithfully reproduce it — `run_code`
parameters are per-call and have no stable workflow mapping, so the escalation
would silently run something different. **Deferred for later**: a real
"promote to validated workflow" needs a reproducible parameterization of the
ad-hoc code (or a mapping from the run_code intent to a catalog workflow).
**Fix (done):** removed the button render in `chat-message.tsx`; the
handler/prop plumbing (`handleRedoAsValidatedRun`, `onRedoAsValidatedRun`) is
retained unused so re-enabling is a one-line render restore.
