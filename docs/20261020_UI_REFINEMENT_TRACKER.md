# UI refinement tracker (2026-10-20)

Per-item loop for each reported detail issue: **document → fix → test →
re-capture screenshot → audit → confirm**. Left = `data_centroid_design_v2`
reference, right/real = live BioMate platform.

---

## Item 1 — Sidebar + API Keys (`sidebar_comparison.png`, `stand_alone_apikey_notcomplete.png`)

### Sidebar (WORKSPACE nav)
- **1a. `Data` item present** — real sidebar has **Data** in WORKSPACE; the design
  does not. Design WORKSPACE = New chat · Workflows · Connectors · Models · IND Report.
  Real = New Chat · Workflows · **Data** · Models (missing Connectors + IND Report).
  → reconcile nav to the design (confirm whether Data stays or is removed).
- **1b. Project-item color** — under a project, the design renders Files/Runs/
  Instructions/chat titles in **blue**; the real platform renders them gray/dark.
  → apply the design's blue to project children.
- **1c. BETA tag** — real logo shows "BioMate AI **BETA**"; design has a clean
  wordmark, no BETA. → remove BETA.

### Sidebar (chats under a project)
- **1d. Blank "New Chat" pile-up** — the real sidebar accumulates many empty
  "New Chat" rows (7+). Should **dedupe** and **auto-remove** an untouched empty
  chat after a while (never created unless edited).
- **1e. New-chat routing bug** — BOTH the top-level "New Chat" AND a project's
  "New Chat" create the chat under the **first** project. A new chat from the top
  bar should be unfiled (or scoped correctly); a project's "New Chat" should land
  in **that** project. Behaviour for the 2nd project is wrong/unverified.

### Sidebar (bottom — Settings & API)
- **1f. Settings/API shown ad hoc + overlapping** — design has one clean
  **"Settings & API Keys"** row above the user block; the real platform shows
  Settings/API ad hoc, overlapping the bottom settings gear. → single clean entry.

### API Keys dialog (`stand_alone_apikey_notcomplete.png`)
- **1g. Standalone dialog** — "API Keys" opens as its own modal with only
  "API Keys" in its left nav (standing alone), not integrated into Settings.
- **1h. Modal overflow** — the modal is too tall; its bottom (Anthropic BYOK row)
  is **cut off** below the viewport. → cap height + scroll inside the modal.

Status: documenting + investigating the sidebar component.

---

## Item 2 — User-cancelled run shows "Failed" (`Usercancer_not_fail.png`)
A user-cancelled run renders **"RUN FAILED"** (red) with "Cancelled by user" — in the
After-run panel, the sidebar dot beside the project, and the status bar. A cancel is
not a failure. Backend fix (status stays `cancelled`) committed (`nextflow_executor`);
the **frontend must render `cancelled` as a neutral "Cancelled" state**, not red "FAILED",
everywhere (panel badge, sidebar status dot, status bar).

## Item 3 — Void "(why?)" links (`why_void.png`)
The "(why?)" links next to workflow-step chat messages lead nowhere. → if the
explanation feature is confidently implemented, wire it; otherwise **remove the links**.

## Item 4 — Merge the two After-run download links (`merge_download_select.png`)
The After-run header has two separate links — "↓ Download report" (md) and
"↓ Download deck (PPTX)". → merge into **one** "Download" control that unfolds a
small menu (Markdown report · PPTX deck). **DONE** (commit `bf815213f`).

---

## Item 5 — Rerun / "Run again" is not traced in the chat (`no_obvious_time_sessionsplit.png`)
Rerunning a workflow **overwrites the previous run in place** instead of recording
a new user action + a new BioMate response, so the chat timeline mixes a previous
session's findings with a new session's progress stream (split by a stray BioMate
avatar). Expected: clicking rerun should (a) append a USER message ("run again" +
timestamp) and (b) a NEW assistant workflow-card message bound to the new run —
leaving the prior run's findings intact as their own block.

Verified call chain (Explore): completed "Run again" (footer, `nextflow-workflow-viewer.tsx:4033`)
→ `handleExecute()` → `onExecute` prop → `chat-with-artifacts.tsx handleRunWorkflow`
(`:1245-1283`), which finds the existing `metadata.type==='workflow'` message and
**overwrites its `invocationId = run.id`** (`:1273-1276`) — appends NO new user/assistant
message. Step/failed/QC paths POST `/api/workflows/runs/:id/rerun`, read a fresh
`run_id`, and `setRerunRunId` to swap `activeRunId` in place (even more in-place).
A rerun DOES create a new server run row (new `run_id`, with `parentRunId`/`runSequence`
chaining available) but no new chat message client-side, and there is no per-panel
multi-run history (one `currentRun`, one workflow message, one `invocationId`).
**Fix point:** `handleRunWorkflow` — append a new user + assistant workflow message
(via `chatHistoryService.addMessage`) carrying the new `run.id`; the `lastWorkflowMsgId`
auto-open effect + `runMatchesPanel` already key off the latest workflow message, so
the panel binds to the new run without clobbering the prior one. Status: NOT fixed.

---

## Item 6 — Data panel ≠ design (`datapanel_biomate.png` vs `dataset_design.png`, `dataset_output_view_biomni_unscroll.png`)
Large discrepancy between the platform Data panel and the design
(`reference/claude_design/data_centroid_design_v2/dataui/DataHub.jsx`).

**File tree (`project-file-tree.tsx`)** — gaps vs design `FileTree`:
- No **Search files** box (design has one). → add client-side filter.
- No **version chip (`v2`)** on file rows (design shows them). *(Backend: version
  history is a note-log; a per-row v-count needs data — defer unless cheap.)*
- "Upload" button + refresh vs design's "＋ Add"; quality dots DO match.

**Dataset object (`dataset-object.tsx`)** — decisions (user, 2026-10-20): **follow the
design fully.** Target = design's dataset object:
- Header "Open in": **Jupyter / RStudio / Plot viewer + Ask in chat** (file-type aware).
  Current header = Export RO-Crate / Use-in-chat / Run-QC / Download — **wrong**.
  → remove RO-Crate from header (design puts "Export for deposit" in the provenance
  tab); rename Use-in-chat → **Ask in chat**; add the Open-in launchers.
- Tabs: **Preview | Versions | Where it came from**. Preview has a **Table | Columns
  | Plot** toggle + **Edit → Save as new version** + "Ask BioMate to edit this".
  Current tabs = Preview(+quality+identity folded in, long scroll) | Lineage(raw run
  id) | Versions(hollow). → restructure to the design; move quality/identity/origin
  into "Where it came from"; make Preview compact.

**Verified header-action status (user challenged "have you tested them"):**
- **Use in chat** — WIRED (`chat-input.tsx:233` reads `?attachFile=`, attaches a chip).
  Works but gives no visible feedback. Requires active project == `?project=`.
- **Run full QC** — **BROKEN**: `App.tsx:167` stripped the whole query on `?draft=`,
  deleting `attachFile` before the composer read it → file never attached, only the
  prompt pre-filled. **FIXED** (App.tsx now strips only `draft`).
- **Export RO-Crate** — WIRED (`GET /api/datasets/:ref/ro-crate`) but deposit-time
  jargon, and the design keeps it in "Where it came from", not the header. → relocate.

**Backend capability matrix (audited `datasets_object.py` / `data_perception.py` / Node):**
| Capability | Status | Note |
|---|---|---|
| version-history | PARTIAL | synthesized `v1 · current` + append-only NOTE log; never real multi-version bytes |
| edit → new-version content | **MISSING** | no endpoint writes edited bytes; POST only appends `{note,author}` — the design's "editable → new version" needs **new backend** (copy-on-write + edit-save) |
| lineage name+status | PARTIAL | real workflow name+status while the producing run is still tracked; UUID-only once it ages out (no persistent provenance store) |
| consumers | PARTIAL | real but ephemeral; usually empty |
| IT staging (dataset → Jupyter/RStudio) | PARTIAL | composable: presign (`/files/:id/url`) → `/api/datasets/import-url` (→ hdaId+historyId) → `/api/interactive/launch`; Jupyter/RStudio open on the session history (don't bind the specific HDA). No single endpoint. |
| per-column stats | MISSING | profile returns column NAMES + 8 sample rows only |
| plot data (distributions) | MISSING | no histogram/distribution output |

Implication: "editable → new versions" and the "Columns/Plot" views need backend
work; "Open in Jupyter/RStudio" is deliverable by composing 3 existing endpoints
(stage into session history, then launch). Status: NOT fixed (build in progress).

---

## Item 7 — After-run panel overcomplicated, errors in multiple places
User: "overall, the afterrun panel is overcomplicated, with errors in multiple
places." → audit `AfterRunReport.tsx` (+ merged Results view) against the design;
simplify; fix the errors. (Download-merge, item 4, is one de-clutter step done.)
Status: NOT started (needs a per-state audit vs design).

---

## Item 8 — "Data upload dialogue" redundant (reported earlier, not yet fixed)
User (earlier): "the current data upload dialogue … too much text, no need to
mention 32 files. the functions are also redundant, the history tab has additional
three tabs." = `GalaxyDatasetBrowser` (chat composer "attach data" dialog).
Current source: top tabs = **session · project · history · url** (4); HistoryTab is
a two-level drilldown (histories list → datasets) with count badges
(`{count} items` / `{h.count} datasets`). The "three tabs under history" in the
report does not match current source → the live dev build may differ; confirm the
current screenshot before flattening so the right element is simplified. Clear wins:
drop the count-badge text; collapse the overlapping browse sources. Status: NOT fixed.

---

## Item 9 — Interactive "Data to Load" shows 0 B for every file (`interactivePanel_0filesize.png`)
The InteractiveLauncher output-selection list renders `formatFileSize(output.size)`
(`interactive-launcher.tsx:336`) and every row shows **0 B** → `output.size` is 0/
missing at the CALLER that builds the `outputs` prop. Fix: populate real sizes from
the run's output-file records at the call site. Status: NOT fixed (locate caller).

## Item 10 — Parameter editing cramped for long/array values (`parameter_edit_inconvinient.png`)
In PARAMETERS, "Smiles List" (a JSON array) is shown in a tiny single-line input that
truncates (`["CC(=O)Oc1ccccc1C…`). Long/array/multiline values need a larger editable
field (textarea / expandable). Fix in the param input renderer. Status: NOT fixed.

## Item 11 — Full Step View shows invalid/empty details for a COMPLETED step (`invalid_step_details.png`)
`steps/step-detail.tsx` "FULL STEP VIEW · COMPLETED" shows "tool not reported", "0
outputs", "duration n/a", "0 not default", "No parameters were recorded" — none of the
step's real metadata (tool, outputs, params, duration) is populated for a finished step.
Likely the per-step record isn't persisted/fetched after completion (step parser /
run metadata). Status: NOT fixed (needs data-source trace, likely backend).

## Item 12 — Chat ↔ step-view split not resizable (`view_width_not_editable.png`)
A panel resizer exists for the workflow panel (`chat-with-artifacts.tsx:531`
`panelWidth` + `handlePanelResizeStart:1724`), but in the FULL STEP VIEW mode the split
has no draggable divider. Fix: expose the resize handle (or a drag divider) in the
step-view layout too. Status: NOT fixed.

## Item 13 — Remove "Run again with edits" button in Resolved parameters (`wrong_input_wrong_rerunwithedit_button.png`)
The blue "↻ Run again with edits" button in the after-run Parameters/Reproducibility
tab (`AfterRunReport.tsx:1872`) dispatched `biomate:run-again-with-edits`, which
launched immediately — the "with edits" label was wrong (no edit step). **REMOVED**
(commit pending). The failed-run section keeps its own retry button (`:485`, useful
after a failure). Re-running with edits lives on the panel footer "Run again" (opens
the editable param view).
Sub-note (not fixed): the same screenshot shows `dataset: QUICKSTART.txt` in the
resolved params for an ADMET run whose real input is `smiles_list` — a spurious/
wrong `dataset` param captured in the record. Separate param-resolution bug; trace
where the `dataset` value is injected for a SMILES-list workflow.

---

## Meta — "over-complicating the system in many modules"
Guiding correction: simplify toward the design; remove duplication (e.g. the orphan
`DatasetDialog` "Select or Upload Datasets" is defined but rendered nowhere — a dead
duplicate of the real `GalaxyDatasetBrowser`). Prefer removing/merging over adding.
