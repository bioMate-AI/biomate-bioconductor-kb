# 2026-11-04 — Issue #9: after-run UX on failed / partial runs

Three related bugs where a FAILED or partial Nextflow run presented its own
execution bookkeeping as if it were scientific output. All three fixed in the
frontend; no backend / executor changes.

## FIX #9.1 — Nextflow `pipeline_info` shown as scientific "Outputs"

When a run fails before producing results, Nextflow still writes `dag.html`,
`report.html`, `timeline.html`, `trace.txt`, `execution_report*`,
`execution_timeline*`, `execution_trace*` under `pipeline_info/`, plus the
`.nextflow.log`. The after-run **Outputs** tab listed these in the primary file
table and counted them in "Download all (N) as ZIP" → a failed run looked like
it had produced data.

**Fix** (`frontend/client/src/v2/AfterRunReport.tsx`):
- Added exported helper `isRunMetadataFile({path,name})` that detects run
  metadata by path/name: anything under `pipeline_info/`, `.nextflow.log`
  (incl. rotated `.N`), `execution_(report|timeline|trace)*`, and the bare
  default Nextflow names `dag.html` / `report.html` / `timeline.html` /
  `trace.txt`.
- `OutputsTab` now splits `effectiveOutputs` into `scientificOutputs` and
  `metadataOutputs`. The primary table, `InteractiveToolsRow`, and the
  "Download all (N)" count all use **scientific** outputs only.
- Metadata is **not hidden** — it renders in a collapsed `<details>` labeled
  "Run metadata (Nextflow) · N" (testid `run-metadata-section`) with per-file
  view/download links, so it's still available for debugging.
- Empty-state handling: if there are no scientific outputs but metadata exists,
  the tab shows "No scientific outputs — only Nextflow run metadata is
  available." and still renders the metadata section.

## FIX #9.2 — "Download report" offered on a failed run

The header "Download report" button (`afterrun-download-report`) appeared in all
states. On a failed/cancelled run it stitched a findings-free markdown document.

**Fix** (`AfterRunReport.tsx` header): when `isFailed`
(`executionStatus ∈ {failed, cancelled, error}`), render a muted
"No report — the run did not complete" note (testid `afterrun-no-report`)
instead of the download button. The existing `FailedRunSection` (error context
+ Run again) is unchanged.

## FIX #9.3 — HTML outputs render as a blank box

`step-output-preview.tsx` rendered HTML via
`<iframe src={content.url} sandbox="allow-scripts" className="... h-64 ...">`.
JS-driven pipeline reports (Nextflow `dag.html`/`report.html`, MultiQC) need
same-origin storage/XHR and real height, so in a 256px `allow-scripts`-only
sandbox they render blank.

**Choice: option (b) — "Open full report in a new tab"** (not relaxing the
sandbox). Reasoning:
- For the `html` viewer, `content.url` is a **`blob:` object URL** minted from
  the app's own origin (the viewer fetches the step-file and does
  `URL.createObjectURL`). A sandboxed iframe with `allow-scripts
  allow-same-origin` on a blob URL **inherits this app's origin**, so arbitrary
  report HTML could read our cookies / `localStorage` and call our credentialed
  APIs → stored-XSS. Adding `allow-same-origin` here is actively dangerous.
- A 256px pane cannot usefully display a full Nextflow report anyway.
- Opening it as a new **top-level** tab is an isolated browsing context;
  `rel="noopener noreferrer"` severs `window.opener` so the report can't reach
  back into our page.

**Fix** (`step-output-preview.tsx`, `case 'html'`): replaced the iframe with a
styled affordance — an `ExternalLink` icon, a short explanation, and an
`<a href={content.url} target="_blank" rel="noopener noreferrer">Open full
report in a new tab</a>`. Other viewers (image, pdf, tables, text, etc.) are
unchanged. Note: the separate inline-preview modal in `AfterRunReport`'s
OutputsTab uses an un-sandboxed, same-origin, 480px iframe and already renders
correctly, so it was left as-is.

## Tests (no mocked API in behavior — pure RTL unit coverage)

`frontend/client/src/v2/AfterRunReport.test.tsx`:
- `isRunMetadataFile` — classifies all pipeline_info/execution/`.nextflow.log`
  variants as metadata; genuine outputs (results.tsv, `multiqc_report.html`,
  volcano.png, predictions.csv, sample.vcf) as scientific.
- Outputs tab: "Download all (1)" with a mixed 1-scientific/3-metadata set
  (never "(4)"); metadata grouped under `run-metadata-section` ("· 3").
- Failed run: `afterrun-no-report` shown, `afterrun-download-report` absent;
  completed run keeps the download button.

`frontend/client/src/components/step-output-preview.test.tsx`:
- `.html` routes to an "Open full report in a new tab" link with
  `target=_blank`, `rel="noopener noreferrer"`, `href=blob:…`, and **no**
  `<iframe>`.

## Gate results

- `npx tsc --noEmit -p .` — clean.
- `npx vitest run step-output-preview AfterRunReport nextflow-workflow-viewer`
  — 44 passed / 3 skipped (was 37/3; +7 new).

(Gates run via a temporary `node_modules` symlink to a sibling checkout because
this isolated worktree has no install; symlink removed after. `node_modules` is
gitignored.)

## What still needs a live run

- Visual check on dev that a real failed ADMET/RNA-seq run now shows the
  metadata section collapsed, the scientific count honest, the "No report" note,
  and that a Nextflow `report.html` opens in a new tab and actually renders.
- Confirm the backend output-file listing doesn't tag `pipeline_info` files with
  a `step` that would re-surface them (path-based detection already covers the
  `pipeline_info/` prefix regardless of the `step` field).
