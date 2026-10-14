# Screenshot committee review — BioMate user-manual end-to-end screenshots

**Date:** 2026-10-13 · **Committee:** OpenAI `gpt-6.1-sol-pro` + Google `gemini-3.1-pro-preview` + Anthropic `claude-opus-5.5` (all via OpenRouter), each independently reviewing **all 56** `docs/user-manual/assets/*.png` on 4 axes (screen quality, UI elements, content correctness, clarity) against each shot's intended `CAPTURE` state.
Runner: `research/screenshot_committee/review.py` → `results/committee_raw.json`; aggregation → `results/aggregated.json`.
**This is a review/sanity layer, not validation.** Raw verdict tally: **121 major / 37 minor / 8 ok** (168 verdicts); **39/56 assets are consensus-major** (≥2 models).

## Executive summary — what actually matters

### A. Real UI / product / content bugs the committee caught (fix in the product, not the screenshot)
1. **CRO Library capture is a `Page not found` (404).** `i13-1-cro-library.png` shows an error page, not the CRO library — either `/drug-discovery-cro` was broken when captured or the capture hit an unauth/route error. **Investigate the route**; the asset is unusable until re-shot against a working page.
2. **Multi-objective design — accept logic contradicts the displayed gate.** `i11-3-multi-objective.png`: candidates BM-0001–BM-0004 are **"Accepted" despite `property_envelope = 0` failing the stated "≥ 1 target"** (flagged by OpenAI + Google). Either the accept rule or the displayed threshold is wrong — a genuine content/logic inconsistency to reconcile.
3. **Failed/mid-run panel shows contradictory status.** `r-fail-state.png`: overall progress vs per-step progress conflict, and "QC blocked / adjusting" coexists with a "Done" status. Real state-rendering inconsistency worth a product look (captured during the ADMET QC-gate moment).
4. **Two similarly-named download buttons confuse even expert reviewers.** On `i09-1`, `i09-2`, `r-merged-results-view` all three models flagged the top-right **aggregate "Download report"** as stale/confusing next to the new **"Download findings"**. The aggregate button is *intentional* (stitches all tabs) — so this is a **UX-clarity** issue, not staleness: if 3 frontier reviewers misread it, users will too. Consider renaming it (e.g. "Download full report") or disambiguating in-UI.
5. **Connectors dialog** (`i12-1`): tab label doesn't match the intended state and the data-residency copy reads as conflicting — verify the content.

### B. Systemic CAPTURE-quality issues (fix in the capture harness, not the product)
- **Ugly fixture data dominates many shots.** Project names like `E2E File Tree 1789241690756`, duplicate/near-identical project cards, orange "Watch" quality pills instead of a clean green example (`i05-*`, `m2-1`, cold-start). → **Seed a clean, reader-facing demo project** (good names + example data + a versioned, green-quality dataset) and capture against it.
- **Crop / dead space / clipped previews.** Most assets are full-viewport with large empty margins; several inline previews are clipped with no scroll cue. → **element-scoped crops** in the harness.
- **Wrong state captured.** e.g. `m2-1` shows the "Ad-hoc compute" tab, not "Validated workflows"; several shots don't match their intended `CAPTURE` state. → the harness should **drive to the intended state** before shooting.

### C. Coverage gaps (the bigger foundation issue)
- **17 assets are `unreferenced`** (not linked from any manual page) — orphaned captures.
- **Whole domain use cases have ZERO screenshots.** The per-use-case table below covers T0/T3/T10/T11/W2 + some modules, but **cryo-EM, single-cell, variant-calling, proteomics, metabolomics, metagenomics, epigenomics, structural-biology, multi-omics, CRISPR** have **no end-to-end screenshot sequence at all**. If end-to-end screenshots are the foundation "for each and every use case", these must be captured (each needs its own real run → the run-dependent harnesses).

---

## Per-use-case summary

| Use case / chapter | assets | worst (consensus) | consensus-major assets |
|---|---|---|---|
| modules:I01-getting-started-cold-start | 1 | minor | 0 |
| modules:I05-files-and-dataset-object | 3 | major | 2 |
| modules:I08-outputs-viewers-interactive | 1 | major | 1 |
| modules:I09-reports-and-reproducibility | 1 | major | 1 |
| modules:I10-models | 1 | major | 0 |
| modules:I11-design-and-generate | 2 | major | 1 |
| modules:I12-connectors-and-skills | 1 | major | 1 |
| tutorials:M1-search-and-evidence | 1 | minor | 0 |
| tutorials:M2-data-analysis | 1 | major | 1 |
| tutorials:S1-sidebar-navigation | 1 | major | 1 |
| tutorials:T0-getting-started | 1 | major | 1 |
| tutorials:T10-exploring-your-datasets | 5 | major | 4 |
| tutorials:T11-drug-development-end-to-end | 2 | major | 2 |
| tutorials:T2-models-and-the-closed-loop | 3 | minor | 0 |
| tutorials:T3-running-a-workflow-and-reading-the-report | 4 | major | 4 |
| tutorials:T6-connecting-instruments | 2 | major | 1 |
| tutorials:T7-projects-and-collaboration | 2 | major | 2 |
| tutorials:T9-connecting-data-and-tools | 1 | minor | 0 |
| tutorials:W1-workflow-panel-tabs | 2 | major | 2 |
| tutorials:W2-after-run-panel | 4 | major | 4 |
| unreferenced | 17 | major | 11 |

## Prioritized fix list — consensus major (≥2 of 3 models)


### BUG+CAPTURE (39)

- **i05-0-data-hub.png** _(tutorials:T10-exploring-your-datasets)_ — 3/3 major. Capture a selected project with the left file tree and a result CSV open on the right, including its header and tabs.; Repeated project labels make selection ambiguous; the top two cards appear identical.; Crop excess empty space.
- **i05-1-file-tree.png** _(modules:I05-files-and-dataset-object)_ — 3/3 major. Missing per-run output folders required by the intended state.; Quality dots are not present on every row as described.; Large unselected detail pane dominates the screenshot.
- **i05-2-dataset-header.png** _(modules:I05-files-and-dataset-object)_ — 3/3 major. Use a dataset with a green quality pill instead of orange 'Watch'.; Select a dataset with at least one version so the header version-count chip appears.; Crop more tightly around the dataset header to remove excessive dead space.
- **i09-1-three-tabs.png** _(unreferenced)_ — 3/3 major. Remove stale top-right 'Download report' action; retain 'Download findings'.; Identify Compound 1 in summary badges or summarize both compounds.; Tighten side margins and avoid clipping the bottom explanatory text.
- **i09-2-reproducibility-record.png** _(modules:I09-reports-and-reproducibility)_ — 3/3 major. Replace 'Download report' with 'Download findings'.; Expand Resolved parameters to match the intended state.; Compute checksums for a more informative SHA-256 example.
- **i11-3-multi-objective.png** _(modules:I11-design-and-generate)_ — 3/3 major. BM-0001–BM-0004 are Accepted despite property_envelope 0 failing the displayed ≥1 target.; Intro denies a blended number, while the footnote defines score as a mean of normalised objective scores; distinguish ranking aggregation from optimis; [ui_elements] Columns and rows are complete and aligned; no clipping or broken components visible.
- **i12-1-connectors-dialog.png** _(modules:I12-connectors-and-skills)_ — 3/3 major. Tab label does not match intended state.; Residency explanation conflicts with undeclared execution locations.; Scope preview selectors and checked rows lack an explanation of their effect.
- **m0-1-intent-bar.png** _(tutorials:T0-getting-started)_ — 3/3 major. Lane-preview terminology does not match the intended 'Instant · cited answer' state.; Cloud-confirmation wording differs from the specified line.; Crop includes unnecessary sidebar/account area and cuts tightly against suggestion chips.
- **m2-1-data-analysis-module.png** _(tutorials:M2-data-analysis)_ — 3/3 major. Select Validated workflows and capture a selected domain with workflow rows showing title, required inputs and time, including sample badges.; Current cold-start examples do not visibly establish runnable demo inputs.; Repeated project names and clipped branding distract from the tutorial focus.
- **r-fail-state.png** _(unreferenced)_ — 3/3 major. Overall progress contradicts step progress.; QC review, blocked/adjusting message, and Done status conflict.; Analysis-plan preview starts mid-word.
- **r-merged-results-view.png** _(tutorials:W2-after-run-panel)_ — 3/3 major. Replace the stale top-right 'Download report' action with current terminology.; versions.yml lacks the inline preview promised by the intended state.; Crop empty side margins and use detail shots to keep text readable.
- **r1-prerun-param-strip.png** _(tutorials:T11-drug-development-end-to-end)_ — 3/3 major. Wrong primary view: no generated candidates, rankings, or objective columns.; Malformed required parameter 'CN1C' contains remaining molecule-string fragments.; Pre-run confirmation contradicts the chat's background-run message.
- **r2-running.png** _(tutorials:T11-drug-development-end-to-end)_ — 3/3 major. QC maximum-percentage gate shows ≥ rather than an upper-bound comparison; verify label/operator.; Analysis preview begins 'ed drugs', appearing clipped.; Excess blank chat space and bottom-cropped composer reduce screenshot focus.
- **r2b-running-metrics.png** _(unreferenced)_ — 3/3 major. Remove stale 'Generating workflow...' text once execution starts.; Capture the complete opening description rather than starting mid-sentence.; Remove literal backticks from code pills and use reader-friendly QC labels.
- **r5-outputs.png** _(tutorials:W2-after-run-panel)_ — 3/3 major. Wrong screenshot focus: output-file previews instead of the populated Findings Summary card.; Required summary, metric chips, expanded Key Results, and Download findings button are absent.; Long, small-text capture with clipped preview content is difficult to scan.
- **r6-reproducibility.png** _(tutorials:W2-after-run-panel)_ — 3/3 major. Replace obsolete three-tab navigation with Results and Reproducibility record.; Replace Download report with Download findings.; Capture Results with the Findings Summary paragraph, clickable number, headline metric chips, and expanded Key Results; none are shown.
- **r8-completed-chat-and-panel.png** _(tutorials:W2-after-run-panel)_ — 3/3 major. Replace obsolete three-tab report navigation with Results and Reproducibility record.; Both download controls say Download report, not Download findings.; Show expanded Key Results and a visibly clickable summary number.
- **s1-1-sidebar.png** _(tutorials:S1-sidebar-navigation)_ — 3/3 major. Replace empty chat history with a few chats, including one coloured status dot, and show its section heading.; Use distinguishable project names; four identical labels appear.; Frame the full sidebar more tightly and prevent logo clipping.
- **t10-1-dataset-preview.png** _(tutorials:T10-exploring-your-datasets)_ — 3/3 major. Open a real results CSV and show meaningful column headers, first rows, and the 'First N rows of M' note.; Crop more tightly around the dataset detail panel to remove dead space.; [ui_elements] Preview is active; tabs, actions, and identity rows are aligned with no visible overlap or broken controls.
- **t10-4-dataset-versions.png** _(tutorials:T10-exploring-your-datasets)_ — 3/3 major. Missing required added version entry (v2), note, author, and timestamp.; Excessive lower-page dead space; crop around the dataset panel.; Redundant current label and current badge.
- **t11-3-pareto.png** _(unreferenced)_ — 3/3 major. All plotted candidates are marked dominated with no nondominated frontier shown; verify classification/count.; Missing numeric axis scales and vertical-axis range.; Oversized container leaves substantial dead space.
- **t3-1-workflow-panel.png** _(tutorials:T3-running-a-workflow-and-reading-the-report)_ — 3/3 major. Replace completed After run view with active Workflow settings in idle pre-run state.; Show expanded Parameters strip, Required parameters, one flagged empty required field, and disabled Confirm-and-run.; Update stale report tabs and download label.
- **t3-3-after-run-outputs.png** _(tutorials:T3-running-a-workflow-and-reading-the-report)_ — 3/3 major. Missing visible step grouping; all artifacts show 'run'.; No report heading or completion status establishes the intended context.; Long, repetitive expanded previews obscure the output overview and truncate content.
- **t3-4-after-run-reproducibility.png** _(tutorials:T3-running-a-workflow-and-reading-the-report)_ — 3/3 major. Replace Summary/Outputs/Reproducibility record tabs with Results/Reproducibility record.; Replace 'Download report' with 'Download findings'; the intended-state note is outdated.; Neither 'Reproducibility bundle' nor 'Download all as ZIP' is shown.
- **t6-1-instruments-tab.png** _(tutorials:T6-connecting-instruments)_ — 3/3 major. My instruments shows 'No instruments registered yet' instead of the required instrument row with status and residency badges.; Crop more tightly around the dialog to improve manual readability.; Missing instrument row with status and residency badges in the 'My instruments' section.
- **t7-0-project-overview.png** _(unreferenced)_ — 3/3 major. Standing instructions heading is partially obscured by the Members & Roles panel.; BioMate branding is clipped at the sidebar's right edge.; Right-panel explanatory text is cut off at the bottom.
- **t7-1-standing-instructions.png** _(tutorials:T7-projects-and-collaboration)_ — 3/3 major. Standing instructions lacks the required filled content and 'Read by the assistant on every chat in this project' subtitle.; Members & roles appears immediately below Standing instructions; the expected empty Notes card and 'Private' label are absent.; Excessive empty Files space weakens focus on the right rail; bottom explanatory text is clipped.
- **t7-2-members-roles.png** _(tutorials:T7-projects-and-collaboration)_ — 3/3 major. Missing postdoc (Editor) and collaborator (Viewer), each with a role dropdown.; Share link is not generated; Copy and Revoke controls are not shown.; Permissions-card explanatory text is clipped at the bottom.
- **w1-0-panel-overview.png** _(unreferenced)_ — 3/3 major. Replace obsolete after-run tabs and download label.; Resolve workflow-name mismatch: Debug Workflow versus Untitled Workflow.; Provide actionable guidance for repairing output access.
- **w1-1-phases.png** _(tutorials:W1-workflow-panel-tabs)_ — 3/3 major. Capture after one step is DONE while another is RUNNING.; Correct alt text: this is a live run, not finished results.; Resolve inconsistent elapsed times (0s wall clock versus 6s active step).
- **w1-2-workflow-settings.png** _(tutorials:W1-workflow-panel-tabs)_ — 3/3 major. Missing file field with Browse and AI-filled value with badge/Override.; Missing 'Your permissions here' card described by the alt text.; Required fields are empty despite Default badges; numeric control types are not apparent.
- **w2-failed-run.png** _(unreferenced)_ — 3/3 major. Replace obsolete report tabs and download label.; Failure panel shows only a Nextflow Graphviz WARN, not a clear failure cause.; Crop substantial empty space below report content.
- **w3-1-step-row.png** _(unreferenced)_ — 3/3 major. Top parameter line and lower workflow row are clipped.; Only a narrow workflow fragment is shown, making this unsuitable as a standalone manual screenshot.; Mixed English and Chinese labels reduce documentation consistency.
- **i08-1-outputs-tab.png** _(modules:I08-outputs-viewers-interactive)_ — 2/3 major. Generating steps are not identifiable beyond 'run'.; Use a shorter crop with fewer expanded previews and visible Outputs context.; Preview text is clipped without a visible scroll cue in several panes.
- **i13-1-cro-library.png** _(unreferenced)_ — 2/3 major. Page-not-found capture is unsuitable for workflow documentation unless explicitly illustrating error recovery.; Large blank margins should be cropped.; [content] Shows 'Page not found' rather than a product workflow; error copy and 'Back to BioMate' label are consistent.
- **t10-2-dataset-lineage.png** _(tutorials:T10-exploring-your-datasets)_ — 2/3 major. Missing required Status row.; Live provenance is no longer retained for the displayed run.; Large unused lower area; crop closer to the lineage panel.
- **t11-2-design-candidates.png** _(unreferenced)_ — 2/3 major. Pass labels conflict with the displayed property_envelope threshold; clarify whether this target is advisory or correct the conclusions.; [ui_elements] Table columns and repeated actions are consistently aligned; no broken components visible.; [quality] Sharp, legible, fully framed; no clipping or overlap.
- **t3-2-after-run-summary.png** _(tutorials:T3-running-a-workflow-and-reading-the-report)_ — 2/3 major. Actual findings are displayed instead of withheld; the intended withholding explanation is absent.; Crop omits tab navigation, so the Results-tab context is not established.; [content] Shows completed ADMET predictions and interpreted numerical findings for two compounds, contradicting the intended findings-withheld state. 
- **w3-2-fullstep-provenance.png** _(unreferenced)_ — 2/3 major. Capitalize ADMET correctly.; Replace '0 not default' with '0 non-default parameters'.; Missing run details limit instructional value; screenshot is not referenced by any manual page.

## Committee & honesty
- Roster: OpenAI `openai/gpt-6.1-sol-pro`, Google `google/gemini-3.1-pro-preview-customtools`, Anthropic `anthropic/claude-opus-5.5` — each reviewed all 56 assets independently via OpenRouter.
- Model errors/empties (honest gaps): 2 — i11-1-design.png:anthropic, t11-1-composer-goal.png:anthropic
- This is a **review/sanity layer, not validation** — it flags quality/correctness; it does not replace a human design pass.

## Bucket C follow-up — domain end-to-end execution diagnosis (2026-10-13)

Parametrized harness (`frontend/e2e/domain-e2e-capture.e2e.ts` + `domain-results-capture.e2e.ts`, commit `9721a9ad0`) drove the 6 CPU-cheap self-contained cold-start examples against dev.

**Routing: 6/6 correct** (new coverage win — these domains had zero e2e screenshots). Committed 8 assets (6 `domain-*-prerun.png` + 2 `-running.png`, all 2×). **No completed/results figure** committed — the runs genuinely do not finish, and shipping "completed" chrome over a failed run is forbidden by CLAUDE.md.

Root-cause diagnosis of the execution gaps (read-only, via fixture `/api/workflows/runs`):

| Domain | Routed to | Run outcome | Root cause |
|---|---|---|---|
| single-cell | `nf-core/scdownstream` | **failed pre-flight (404), 0 Batch spend** | Script not resolvable: `Could not resolve Nextflow script 'nfcore/scdownstream/main.nf'. Set NEXTFLOW_SEARCH_ROOTS…`. Catalog entry points at a `.nf` not deployed at the resolver's search roots. Example (`singlecell` demo) pins no workflow → routing picks an undeployed pipeline. |
| metabolomics | `metaboanalystr_timeseries` | **ran on Batch ~20 min, failed** (run `4f03d6cc`) | Workflow↔data mismatch. Log: `qs2::qs_read could not read .qs/.qs2 file: asca.qs` → `BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA failed`. The human_cachexia demo is cross-sectional 2-group; a two-factor ASCA (time-series) step has no axis to decompose → emits no valid `asca.qs`. Example says "metaboanalystr" generically → routing picked the timeseries variant. |
| epigenomics, proteomics, CRISPR, variant-calling | chipseq/macs, chemoproteomics_pulldown, mageck, sarek | **Confirm clicked, no run persisted** | Overlaps a concurrent session's active launch-resolution / projectId debug (`20083555e`, cf. `7749049d3`). Not re-diagnosed here to avoid duplication. |

**Recommended fixes (routing/catalog layer — product decision on example targets):**
1. single-cell: either register/deploy `scdownstream` at the resolver roots, or steer the `singlecell` example to a single-cell workflow that is deployed and E2E-verified. (Note `project_workflow_validation_gaps`: single-cell has no real E2E yet — the deeper gap.)
2. metabolomics: steer the example to a non-timeseries MetaboAnalystR workflow matching the 2-group cachexia demo, or give the timeseries workflow a real time-series demo dataset.
3. Harness bug fixed in `9721a9ad0`: `waitForFunction(fn, {timeout})` → `waitForFunction(fn, null, {timeout})` (timeout was being passed as the page-fn arg, silently capped at the 60s actionTimeout).

**GPU domains held for explicit go:** cryo-EM, structural-biology/AlphaFold, histology nuclei-seg. **No self-contained CPU demo located:** metagenomics, multi-omics.

## Re-score (2026-10-13) — after the re-capture passes

Re-ran the 3-model committee on the **36 re-captured assets** (`research/screenshot_committee/rescore.py` → `results/rescore_raw.json` + `rescore_aggregated.json`).

**Validity note (important):** the FIRST re-score run scored **35/36 major** — a *measurement artifact*, not real regressions. Two systematic false-positive sources, both now fixed:
1. The rubric wrongly declared **"Download report" stale**. It is a *legitimate separate* comprehensive-report button that coexists with "Download findings" — so every after-run shot was falsely majored. Rubric corrected (`review.py`).
2. Several **manual alt-text captions were stale** relative to the (correct) re-captured images (e.g. t3-2 "findings withheld" vs. the now-populated findings; r2/r6 tab attributions). Corrected intended-states passed via `CONTEXT_OVERRIDE` (`rescore.py`). Contaminated v1 preserved as `rescore_raw_v1_contaminated.json`.

**Corrected tally: 9 minor · 27 major** (down from the contaminated 35/36).

**Dropped first-pass major → now minor (artifacts resolved, 9):** `t7-2-members-roles`, `t3-2-after-run-summary`, `t3-4-after-run-reproducibility`, `i09-1-three-tabs`, `i09-2-reproducibility-record`, `i11-3-multi-objective`, `t11-2-design-candidates`, `t10-1-dataset-preview`, `t6-1-instruments-tab`.

**Still major — classified honestly (27):**

*(a) Real UI/content bugs — actionable:*
- `r2-running`, `w1-1-phases` — **broken/missing icon placeholders (empty squares) next to the "Running" badge** in the panel header (real render bug on the running state).
- `domain-cryo-em-prerun` — **raw string/object leaking into the "Dataset Id" field** (concatenated identifier/URI).
- `w3-1-step-row` — **step row localized in Chinese** in the EN manual (i18n leak).
- `r6-reproducibility` — raw unstyled `runId: …` text above the header + all SHA-256 cells show a dash (both `/debug/afterrun` capture artifacts; checksums are on-demand).

*(b) Wrong state — re-capture needed:*
- `w1-1-phases` (progress 0/2 — catch one step DONE while another RUNNING), `i05-0-data-hub` (open a result CSV, not `counts_matrix.csv`), `t7-0-project-overview` (the true project overview, not the Instructions page), `t10-2-dataset-lineage` (a run-OUTPUT dataset with "Produced by run" + Status row), `i12-1-connectors-dialog` (the Connectors **dialog-table** with scope selectors + the A5 residency row, not the `/settings/connections` card page).

*(c) Crop / margin / whitespace / fixture-pollution polish (minor dressed as major):* `s1-1-sidebar`, `r5-outputs`, `t3-3-after-run-outputs`, `i08-1-outputs-tab`, `r1-prerun-param-strip`, `t3-1-workflow-panel`, `w1-2-workflow-settings`, `t10-4-dataset-versions`, `t7-1-standing-instructions`, `w3-2-fullstep-provenance`.

*(d) Accepted limitation — prerun-only domains (8 `domain-*-prerun`):* these are intentionally pre-run only (the pipelines aren't deployed on dev, per the approved plan). Residual nits: plural "1 steps", truncated analysis-plan preview text, "background-running claim vs confirmation state" inconsistency; several are also flagged "unreferenced — attach to a page or remove".

**Bottom line:** the re-captures **did** clear the redesign-staleness (merged Results / Download findings / 3-tab nav) and the fixture-pollution/low-res issues that drove the first pass. The honest residual is a **handful of real UI bugs** (running-badge icons, cryo dataset-Id leak, w3-1 Chinese, r6 debug-route chrome), **~5 wrong-state re-captures**, **~10 crop/polish nits**, and the **accepted prerun-only domain limitation** — not a wall of regressions.
