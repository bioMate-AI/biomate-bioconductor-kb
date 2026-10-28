# UI content + appearance audit — findings & fixes (2026-10-28)

Live design-conformance audit of the dev workflow UI against the design spec
(`data_centroid_design_v2/spec`, `claude_code_core/docs`), beyond structural presence —
checking detailed content of each element + appearance. Evidence = real dev screenshots
captured by the e2e run (in_vivo_cart_codesign completed run) + the Files panel.

## Open findings (to fix)

1. **Chat findings = full table, duplicated.** The chat shows findings TWICE: the rich
   "Findings Summary" card (verdict + chips + full 4-row Key Results table + caveats +
   deep-links) AND a second text block ("… — complete. 4 steps completed" + repeated
   verdict + "Key results:" bullets + "Open the Findings panel"). **Fix:** chat = a
   *preview* (verdict + chips) + a link to the full result in **Outputs**, not the full
   table; remove the duplicate text block. (User: "preview in chat, link to full result in
   output".) Component: `findings-card.tsx` (shared chat+panel → needs a `preview` mode),
   chat usage in `chat-message.tsx`/`chat-interface.tsx`.

2. **Quick-feedback modal auto-covers the after-run Summary.** A feedback survey
   (incl. "I would pay $29/month…") pops up over the completed-run results, hiding the
   deliverable. **Fix:** don't auto-open the feedback dialog over the after-run panel; gate
   it / show unobtrusively after dismiss.

3. **Outputs grouped/labelled by a raw step id (`76D11493`).** `AfterRunReport.tsx:1373`
   (group header) and `:1385` (`· {f.step}` per-file chip) render `f.step`, which is an
   opaque hash — "who knows the id?" All 11 files collapsed under one id-group (no real
   per-step attribution). **Fix:** label by the human step/phase **name** (ARC §3.2
   "grouped by phase/step", preview header "from <step>"); if only an id is available,
   resolve it to the step name from the run plan, else suppress the hash — never show the
   raw id as the user-facing label. Trace `f.step` source (likely backend outputs lack
   step names → all get the run/history id).

4. **"Save to Project" is a manual button; should be automatic.** Run outputs already
   belong to the project (Files panel: "run outputs in this project"). **Fix:** outputs
   auto-saved to the project on completion; remove/demote the manual "Save to Project"
   button (or make it a no-op confirmation).

## Known baseline gaps (design-spec already flags; not regressions)

5. **Scientific-chart figure primitives missing.** `v2/blocks/types.ts` `BlockFigureKind =
   bars|composition|qc` only — no dedicated figure for dose-response/4PL, volcano, KM,
   heatmap/tracks. DESeq2 volcano / plate 4PL / s4 KM fall back to generic bars/table.
   (cryoEM FSC has a standalone `fsc-curve-chart.tsx` not wired into the block catalog.)
   Spec itself marks these "placeholder renderer". **Follow-up:** add curve/scatter/KM
   figure kinds + renderers; verify the composer EMITS the right figure block per task.

6. **Outputs tab inline-preview vs Files-panel dataset-object.** Outputs tab uses inline
   accordion previews; the rich dataset-object view (Table/Columns/Plot + Versions + "Where
   it came from" + quality + shape tiles) lives only in the Files panel. Spec (S07 §7.8)
   wants dataset-class outputs to "open as dataset objects". **Follow-up:** wire Outputs'
   dataset-class files to open into the Files dataset-object view ("Open in Files").

## Done this session
- Trajectory commented out (StepDeep + AfterRunReport plumbing); Report already had it
  commented. (`4a539c0da`)
- after-run-audit e2e fixed from the stale 7-tab taxonomy to the approved 3 tabs
  (Summary/Outputs/Report) + content checks. (`4a539c0da`)

## Conformant (positive)
Workflow name correct (not "undefined"); Completed badge + 100% 4/4 progress + `After run ●`
report dot; 3-tab Summary/Outputs/Report; findings entity table with a Source/provenance
column per row; Outputs = file list + inline data preview (FASTA code / text); Files panel =
full dataset object (left list + right Table/Columns/Plot + Versions + lineage + quality +
shape tiles); output-type dispatch (image/table/sequence/vcf/annotation/structure) + block
composition system (`v2/blocks/BlockRenderer`). Palette/typography read as the data-centric
design.
