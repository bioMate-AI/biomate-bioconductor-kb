# Current data-centric UI — screenshots for the claude-design brief

Captured 2026-08-17 from the live **dev** app (`dev-public.biomate.ai`), fixture account, real state. Companion to `docs/20260817_RESOURCE_STRUCTURE_DESIGN_BRIEF.md` (Part 2). These show the *current* data-centric UI & information flow so claude-design can propose a better one.

| File | Data-flow stage | What it shows |
|---|---|---|
| `00_workspace.png` | **Stage 1 — ingest (entry point)** | The three-panel workspace: left sidebar (nav + Projects), empty center chat, and the composer at the bottom with the **paperclip** (upload), a calendar icon, suggested-query chips ("MG patient stratification → ADMET", "ADMET screen from SMILES", …). This is where data/requests enter. |
| `01_runs_history.png` | **Run/data inventory** | The Workflows → **Run History** dialog: rows with status dots (blue running / red failed / green completed), Open / New-analysis buttons, 404 runs / 9 pages. The closest thing today to a "where is my data/work" list — but it's runs, not datasets. |
| `20_run_panel.png` | **Stage 4–5 — the results panel** | A run opened with the **right workflow panel**: RUN FAILED banner (red), Workflow-setup / Phases / **After run** tabs, and the After-Run sub-tabs **Outputs · Findings · QC Gates · Parameters** with a Restart footer. (Failed-run variant — shows how failures surface.) |
| `21_report_findings.png` | After-Run → Findings | The Findings sub-tab of the results panel. |
| `21_report_outputs.png` | After-Run → Outputs | The Outputs sub-tab (where produced data lands). |
| `21_report_parameters.png` | After-Run → Parameters | The Parameters sub-tab. |
| `21_report_qc.png` | After-Run → QC Gates | The QC-gate audit sub-tab. |
| `30_completed_run_panel.png` | **Information flow through chat** | A **completed** ADMET run's chat stream: step-by-step BIOMATE messages (`ADMET_INFER_SHARD` → `PREDICT_ADMET_PROPERTIES` → **"QC blocked on DILI risk — adjusting parameters"** auto-loop → "Workflow finished"). Shows information flowing *back* to the user as prose + step logs. |

## The point these make for design
Data/work is **scattered**: it enters at the composer (00), is inventoried as *runs* (01, not as datasets), streams back as chat prose (30), and its outputs live behind panel sub-tabs (20, 21). **No single view centers on a dataset** and shows its lineage (where it came from → what ran on it → what it produced). That fragmentation is the problem Part 2 of the brief asks claude-design to solve.

## Capture limitations (honest notes)
- **Uploader is a native OS file picker.** Clicking the paperclip opens the browser's native file dialog (confirmed: Playwright `filechooser` event fired), not an in-app panel — so the "Local upload" tab / instant **data card** + QC badge described in User Manual §6 could not be screenshotted headlessly. The composer paperclip in `00_workspace.png` is the entry affordance.
- **The pristine completed-run *panel* isn't shown.** The completed ADMET run whose session we could open (`30`) renders only the chat step-log; its session did not carry an openable workflow-card, so the After-Run panel tabs shown in `20/21` are from a *failed* RNA-seq run. To capture a clean completed Findings/Outputs panel we'd re-run a small workflow (a Batch spend) or find a completed run whose session carries the card — say the word if you want that.
