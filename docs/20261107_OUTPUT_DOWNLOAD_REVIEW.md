# Output identity and download repair

## Observed on dev

The completed `nf-core/scdownstream` run `cb7a1b63-28a0-41ea-9074-9a3f33fd64f2` groups published files using their parent output directory. `custom_thresholds` is a directory under `02_quality_control`, not evidence of a workflow step with that name. The UI repeated the inferred label on every file, then repeated the filename inside each preview.

An authenticated read of the first published PNG returned HTTP 200 and 95,807 bytes with or without `download=1`. The response was labelled `inline` even for the download request. File availability is confirmed for this artifact; this check alone does not prove a browser download succeeds.

## Intended acceptance

- A readable group heading appears once, explicitly identified as an output group rather than a verified producing step.
- Each file card shows its filename once, with one labelled Download control.
- View opens the enlarged file directly, with its filename and a clear Close action. The panel has no Download action: downloading stays on the output card.
- Downloads retain the existing authenticated run ownership and path restrictions. No arbitrary external output URL is fetched.
- Requested downloads are attachments; inline previews retain their existing content security protections.
- Failed requests surface an error rather than silently doing nothing or saving an error response as data.

The frontend batch also contains the requested removal of “AI” from Findings, and a deployment ancestry check. The latter protects updated sync scripts only; the worktree inventory documents old scripts that still lack the guard.

## Verification

Pending final regression and deployed browser checks. No new scientific workflow is needed for this repair: existing owned output artifacts provide the required end-to-end test.

## Report and export hierarchy

The old primary “Reproducibility bundle” link returned HTTP 404 for the reviewed run. Its backend alias returned only a 212-byte JSON metadata envelope, not an archive. The replacement is a technical “Download run record · JSON” action inside the collapsed metadata section, using the existing authenticated canonical record endpoint. It contains the saved run provenance rather than promising a self-contained rerun archive.

The top action is explicitly “Export report”; the ZIP action is explicitly “Download output files”. Duplicate Outputs/Report section labels and the internal Run ID were removed from the visible document. Report tables now use GFM rendering and scoped document styles derived from `reference/claude_design/data_centroid_design_v2/dataui/search-doc.css`. This is a rendering correction, not a claim that all report editing/versioning/evidence features in the prototype are implemented.

The enlarged file viewer has no download action. Images and PDFs open enlarged directly; CSV/TSV, record-array JSON and STAR tables provide 200-row pagination to reach rows beyond the compact preview. HTML reports retain their separate full-view link and existing sandbox restrictions; binary formats still require supported viewers.

## Pre-sync review

The patch changes React/Express only; Galaxy Python, workflow definitions and databases are excluded from this release. Run-file responses retain the existing ownership/path checks and preview CSP, and set attachment disposition only when explicitly requested. The preview pane has one parent-owned title/Close action and no download control. The canonical technical record adds an attachment header without altering its JSON data or default response. Report Markdown uses exact file paths rather than ambiguous basename-only download references. Expected dev checks: the existing PNG downloads with attachment disposition and the same 95,807 bytes/hash; preview remains inline; canonical run record retains 197 outputs and saved parameters; anonymous reads remain denied. No new scientific run is required.

Known limits: HTML reports retain their full-view link rather than an unsafe unsandboxed inline frame; the overlay still needs a complete keyboard focus trap; the current HEAD validation may read upstream file bytes before the native download. These are not claims of full report-design or on-prem streaming parity. The separate QC reconstruction source fix is preserved outside this release pending required Python 3.9 validation and a reviewed cached-record refresh.

Pre-deployment verification: 2,468 frontend tests passed, 42 skipped (234 suites passed, 3 skipped); production build passed. Script tests: 25 passed. Focused output/report/authentication tests: 90 passed, 19 existing skipped; the added modal interaction test also passed in the final full suite. The first sandboxed integration run could not bind localhost (`EPERM`); the final full suite ran with localhost binding enabled. No skipped live scientific/old-chat coverage is represented as passing.
