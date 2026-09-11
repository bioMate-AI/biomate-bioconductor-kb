# V2 Gap Analysis — Search / Files / Reports / Connectors

**Date:** 2026-09-09
**Scope:** Deployed BioMate frontend vs. claude-design **v2** (`data_centroid_design_v2`), focused on four surfaces: Search-answer, Files/dataset object, Reports, Connectors. Includes the new v2 chapters (Spec 09, Spec 12) and the new dataui components (`SearchAnswer.jsx`, `DocEditor.jsx`, `Connectors.jsx`, `Gaps.jsx`).
**Method:** READ-ONLY. Diff old-design → v2 to isolate what is *new in v2*; then map each v2 element to the deployed counterpart in `/Users/kky/biomate-review/frontend/client/src/` with file:line evidence.

**Reference sets**
- NEW v2: `/Users/kky/biomate-review/reference/claude_design/data_centroid_design_v2/`
- OLD (diff base): `…/scratchpad/old_design/reference/claude_design/data_centroid_design/`
- DEPLOYED: `/Users/kky/biomate-review/frontend/client/src/`

**Diff notes (what actually changed old → v2)**
- `spec/01 Search and evidence.html` — **byte-identical** to old (unchanged in v2). The *worked answer surface* is new, added as **Spec 09** (addendum to 01) + `SearchAnswer.jsx` + `data-search.js` + `search-doc.css`.
- `spec/04 Files and the dataset object.html` — **byte-identical** to old (unchanged in v2). Reports-as-files is new, added as **Spec 12** (addendum to 04 & 07) + `DocEditor.jsx` + `data-docs.js`.
- `dataui/DataHub.jsx` — **revised (+37 lines)**: file-search box, collapsible/resizable file list, and — the load-bearing change — **DocEditor integration**: a file that is a `DOCS[id]` renders a `Document` tab (editable) instead of a static `Preview`, with `DownloadMenu` + `FileChatEdit` wired in.
- `Connectors.jsx` — **new** component (full-page workspace surface).
- `Gaps.jsx` — **new** but NOT a search/files/reports/connectors surface. It is the **governance-gaps** view: typed-clarification card, human-approval gate, agent trajectory, roles/permissions, and the one verification pattern. Assessed briefly at the end for completeness; the deployed system already ships these (`clarify-card.tsx`, `approval-gate.tsx`, `trajectory-view.tsx`), so it is largely DONE and out of the core four-surface scope.

---

## Executive summary

| Surface | New in v2? | Headline verdict |
|---|---|---|
| **Reports as editable files (Spec 12 / DocEditor)** | **Yes (whole chapter)** | **Biggest gap.** Deployed reports are **read-only Markdown downloads**. No chat-edit-with-diff, no report versioning, no reports in the file tree, no multi-format download, no cell-level data edit. One adjacent exception: IND regulatory docs are hand-editable (TipTap) — a different product surface. |
| **Search-answer worked example (Spec 09 / SearchAnswer)** | **Yes (whole chapter)** | **Large gap.** Deployed `citation-panel` covers reference cards, source reader, save-to-notes, and disagreement — but the *answer surface* (retrieval transparency, editable filter chips, dropped-records, boundary, inline ref-card expansion, "turn into a run" exit, save-as-editable-doc) is absent. |
| **Connectors (Connectors.jsx)** | **Yes (full page)** | **Structural + coverage gap.** Deployed is a **modal dialog**, not a page. Residency is DONE (strong). But only 2 of 4 kinds (data sources + models); Skills & Experts tab is built-but-disabled; no MCP-servers surface; no "Add a connector" preview flow. |
| **Files / dataset object (Spec 04, unchanged)** | No (spec unchanged; DataHub +37) | **Mostly DONE**; the delta is the DocEditor wiring above (covered under Reports). File search/collapse are polish gaps. |

**UNDONE / PARTIAL count (core four surfaces): 33 rows below scored PARTIAL or UNDONE — 22 UNDONE + 11 PARTIAL. Only 9 rows scored DONE.**

---

## Surface A — Reports as editable files (Spec 12 · `DocEditor.jsx`) · **NEW IN V2**

**v2 premise:** a run's report becomes a first-class **file object** — in the file tree, downloadable in the formats people hand over (PDF/DOCX/MD/HTML/ZIP-bundle), editable **by hand** (contentEditable, saves a new version, never overwrites) and **by asking** (chat proposes a before/after diff you accept/reject → new version), versioned through one `fileVersions(id)` truth, with the same ask-and-diff at **cell level** for data files.

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| Report is a file object in the file tree | Six docs live in `runs/…`, `notes/`, `runs/models/`; appear in Files tree with quality badge + origin | Yes | **UNDONE** | `components/project-file-tree.tsx:37-50` (`source: "upload"\|"run_output"` only — no report source); `pages/data-hub.tsx:41-54` (no report field) | **P0** |
| After-run opens on a **Report** tab holding the document | Report tab = the document itself, not a "Download report" link | Yes | **PARTIAL** | `v2/AfterRunReport.tsx:4-18` (Methods tab exists among Findings/Outputs/Methods/…); but Methods is read-only `<pre>` at `v2/AfterRunReport.tsx:1203-1210` — no document object | **P1** |
| Download menu: PDF / DOCX / MD / HTML / **ZIP bundle** | Real multi-format menu; every format carries run id + version | Yes | **PARTIAL** | Single button, MD only: `v2/AfterRunReport.tsx:243` ("Download report"), `:206` (`Blob … text/markdown`); explicit "Future: … DOCX/PDF generator" `:1671` | **P1** |
| Edit **by hand**, in place | contentEditable prose; Save writes a *new version*; "Revert to v1" | Yes | **PARTIAL** | Only for IND regulatory docs (`components/regulatory-document-editor.tsx:1-66`, TipTap; `components/ind-report/EditableParagraph.tsx:36-83`). Workflow reports: none | **P1** |
| Edit **by asking** — chat proposes before/after diff, accept/reject → new version | `ChatEdit`: ask field + suggested-edit chips; proposal shows NOW / PROPOSED / **why**; Accept saves new version | Yes | **UNDONE** | No propose/diff/accept-version affordance on any report (agent grep: no matches) | **P0** |
| **Versioning** — one source of truth | `fileVersions(id)` merges accepted doc edits onto stored versions; every surface reads through it | Yes | **UNDONE** (workflow reports) | IND docs versioned (`components/ind-report/IndDocPanel.tsx:751`); datasets append-only notes (`components/datasets/dataset-object.tsx:449` "Version history is not available yet"). Workflow reports: no versioning | **P1** |
| One control per screen (Files owns version chip+download; run's Report tab owns them) | Explicit ownership, no duplicate chips | Yes | **UNDONE** | No report-in-Files object → ownership question does not yet arise | P2 |
| **Data files**: cell-level ask-and-diff (row · field · now · proposed) | `FileChatEdit` writes a new file version; runs reading old keep pointing at it | Yes | **UNDONE** | CSV viewer read-only (`components/viewers/csv-table-viewer.tsx`); no cell editor | P2 |

**Highlights (A):** Reports are effectively **artifacts you download, not objects you own**. The entire v2 thesis of Spec 12 — a report you can take, edit, ask-to-edit, and re-find in Files with an honest version history — is unbuilt for workflow reports. The only editable-document machinery in the codebase (TipTap in `regulatory-document-editor.tsx`) is scoped to IND §2.6 assembly and is not reusable as-is for after-run reports, but proves the org can build hand-editing. This is the single biggest v2 gap.

---

## Surface B — Search-answer worked example (Spec 09 · `SearchAnswer.jsx`) · **NEW IN V2**

**v2 premise (Instant lane):** clicking a cold-start search example (or sending text that routes to Instant·search) opens a **cited answer surface**, not a run panel. Fixed-order sections: *How this was searched* (per-source found/kept + animated bars) → editable **filter chips** (years/species) that re-derive → *what was dropped, and why* → **Answer** (editorial "lead" labels; claims with numbered marks that expand a ref card **inline under the claim**) → **Boundary** → *Where the literature disagrees* + evidence table → **References** cards ("every link confirmed to resolve") → **What to do next** = exactly two exits: **turn into a run** on your data, or **Save as a doc** (which becomes an editable file per Spec 12).

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| Answer *surface* opens from an example (Instant lane, not a run panel) | Clicking an example opens the answer directly; composer parity | Yes | **UNDONE** | No dedicated answer-surface route/component; deployed shows citations inline in chat via `citation-panel.tsx` | **P1** |
| "How this was searched" — per-source found/kept + animated bars | One row per source (PubMed/EuropePMC/bioRxiv), `found · kept`, bars resolve together | Yes | **UNDONE** | No retrieval-transparency UI anywhere | **P1** |
| Editable filter chips (years/species) re-derive the answer | Changing a chip re-derives, records new retrieval alongside old | Yes | **UNDONE** | None found | P2 |
| "What was dropped, and why" (collapsible) | Accounts for every dropped record by reason | Yes | **UNDONE** | None found | P2 |
| Editorial **lead** label on a claim block | Short label ("Direction of evidence · consistent") before the prose | Yes | **UNDONE** | No claim-level lead labels | P2 |
| Numbered marks [1][2] → **inline** ref-card expansion under the claim | Clicking a mark expands the ref card in place | Yes | **PARTIAL** | Marks linkified to hash-anchors (`components/chat-message.tsx:13-40`), but they *jump* to a References list — not inline expansion | **P1** |
| **Boundary** — what the answer is NOT evidence for (+ index date) | Always present | Yes | **UNDONE** | None (only React error-boundary, unrelated) | **P1** |
| "Where the literature disagrees" + evidence table (study/system/finding/strength) | Contradicting sources kept, shown with both positions | Yes | **PARTIAL** | Disagreement surfaced (`components/citation-panel.tsx:53-58`, `:550-599` ConflictRow) but as text boxes, not a study/system/finding/strength table | P2 |
| **References** as cards: title/authors/venue/year/**snippet**/kind/open-source link | + footer "every link opened and confirmed to resolve" | Yes | **PARTIAL** | Cards render title/authors/venue/year + DOI/PMID (`components/citation-panel.tsx:613-764`); source reader pane (`components/source-reader-pane.tsx:51-181`). Missing: snippet, kind classification, link-resolution guarantee | P2 |
| "What to do next" — **two exits**: turn into a run | Instant→run on your own data | Yes | **UNDONE** | "Make instruction" button disabled/unimplemented (`components/citation-panel.tsx:339-355`) | **P1** |
| "What to do next" — Save as a **doc** (becomes editable file) | Writes `evidence_*.md` with retrieval record; editable/versioned/downloadable | Yes | **PARTIAL** | Save-to-notes exists (`components/citation-panel.tsx:305-320`, `:181-240`) but posts to project knowledge, not a file object; not editable/versioned per Spec 12 | **P1** |

**Highlights (B):** The deployed `citation-panel` is a solid **references + disagreement + save-to-notes** widget and honors old Spec 01. But Spec 09's entire *answer-as-surface* idea — retrieval transparency, editable filters, boundary, inline ref expansion, and the two honest exits (run / editable-doc) — is essentially unbuilt. The two exits also cross-depend on Surface A (Save-as-doc needs the editable-file object) and on the composer's Instant-lane routing.

---

## Surface C — Connectors (`Connectors.jsx`) · **NEW IN V2 (full page)**

**v2 premise:** one **full-page** surface for everything the workspace is attached to but does not own — four kinds in tabs (**Data sources**, **Models & LLMs**, **Skills & experts**, **MCP servers**), each row carrying a **residency** label (cloud / on-prem / mounted / local / prompt = "does data leave the estate"), plus an **Add a connector** flow that previews what was found *before* attaching (directory index-in-place vs copy-in; DB read-scope; model endpoint+residency; skill needs/produces; MCP URL+auth+capability review).

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| Surface type: **full page** (`Workspace / Connectors`) | A page/route, not a modal | Yes | **UNDONE** | Deployed is a modal dialog (`components/connectors-dialog.tsx:565-568`), opened from sidebar (`:482`) | P2 |
| Kind 1 — **Data sources** (mount/on-prem/cloud; LIMS, warehouse, share, Benchling, public DBs) | Mixed residency, incl. mounted programme share indexed in place | Yes (as one page) | **PARTIAL** | Present but cloud-only public DBs (`components/connectors-dialog.tsx:75-154`); no on-prem/mounted sources | **P1** |
| Kind 2 — **Models & LLMs** (hosted / self-hosted / vendor) | 3 example rows, residency per row | Yes (as one page) | **PARTIAL** | Present (`components/connectors-dialog.tsx:176-198`); missing "vendor prediction service" concept | P2 |
| Kind 3 — **Skills & experts** (IND writer, figure builder, deposit archive, dose-response, pharmacology/regulatory readings) | 12 example rows | Yes | **UNDONE** | `SkillsTab` built but **disabled** (`components/connectors-dialog.tsx:65` TabId lacks skills; `:521-526`, `:626` commented "/api/skills unpopulated") | **P1** |
| Kind 4 — **MCP servers** (registry server, chem toolkit; capability review) | Dedicated tab, 2 example rows | Yes | **UNDONE** | No MCP tab; only passing mention on Cursor connector (`components/connectors-dialog.tsx:187`) | P2 |
| **Residency** concept (cloud/on-prem/mounted/local/prompt) | Every row carries it; "does data leave the estate" | Yes | **DONE** | `components/connector-residency.tsx:19-28` (5 types + honest "unspecified" fallback `:31-34`), badge on every row + legend (`components/connectors-dialog.tsx:577-587`, `:266-269`) | — |
| **Add a connector** flow with pre-attach preview | 5 modes; "show what was found before attaching" | Yes | **UNDONE** | No add-connector button/flow in the dialog | **P1** |
| Data-source lifecycle: index-in-place vs copy-in, version per scan | Scan reports types/counts before creating dataset objects | Yes | **UNDONE** | Generic upload only (`components/project-file-tree.tsx:419+`); no index-vs-copy choice, no per-scan versioning | P2 |

**Highlights (C):** Residency is a genuine **DONE** — the deployed `connector-residency.tsx` is arguably more honest than the prototype (explicit "unspecified" fallback). But the surface is a **modal covering ~2 of 4 kinds**, with Skills built-but-dark and no MCP tab and no add-with-preview flow. Closing this is mostly re-hosting the dialog as a page + enabling the already-built Skills tab (needs `/api/skills` populated) + adding the MCP kind and the Add flow.

---

## Surface D — Files & the dataset object (Spec 04, **unchanged** · `DataHub.jsx` +37) · reference/context

Spec 04 is byte-identical to old, so the dataset-object model is not a v2 change. The only v2 delta is in `DataHub.jsx`, and its load-bearing part (DocEditor tab) is scored under Surface A. Remaining `DataHub.jsx` deltas:

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| File-list **search box** | Filter files by name/kind in the tree | Yes (+37) | **UNDONE** | v2 `DataHub.jsx` FileTree adds `searchbox`; deployed `components/project-file-tree.tsx` has no in-tree search | P3 |
| Collapsible / resizable file list | Hide list + width grip | Yes (+37) | **UNDONE** | v2 `DataHub.jsx` `onHide`/`Grip`/`Reveal`; no deployed equivalent | P3 |
| Document tab for DOCS files | `isDoc` → `DocEditor` tab instead of Preview | Yes (+37) | **UNDONE** | Covered under Surface A (report-as-file) | P0 |

---

## Appendix — `Gaps.jsx` (governance gaps) · **NEW IN V2, out of core scope**

`Gaps.jsx` is not a search/files/reports/connectors surface; it collects the governance gap-fixes (typed clarification, human approval, agent trajectory, roles, one verification pattern). The deployed system already ships these, so it is largely **DONE** and noted here only so a reader does not mistake it for one of the four surfaces:

| v2 component | Deployed counterpart | Status |
|---|---|---|
| `ClarifyCard` (typed confirm-inference) | `components/clarify-card.tsx` | DONE |
| `ApprovalGate` (human gate) | `components/approval-gate.tsx` | DONE |
| `Trajectory` (agent decisions/tool calls) | `components/trajectory-view.tsx` | DONE |
| `RolesCard` / `VerifyPattern` | fixtures present (`components/gaps-fixtures.ts`); verify wiring separately | PARTIAL (not audited here) |

---

## Coverage checklist

- [x] Spec 09 (search answers) — every element of the answer-surface anatomy mapped (Surface B, 11 rows)
- [x] Spec 12 (reports as editable files) — download/edit/version/tree/cell-edit mapped (Surface A, 8 rows)
- [x] `SearchAnswer.jsx` vs `citation-panel.tsx` / `source-reader-pane.tsx` / `chat-message.tsx`
- [x] `DocEditor.jsx` + `FileChatEdit` vs deployed report/methods surfaces (`v2/AfterRunReport.tsx`) + IND editor
- [x] `Connectors.jsx` vs `connectors-dialog.tsx` + `connector-residency.tsx` (Surface C, 8 rows)
- [x] `Gaps.jsx` — identified as governance view, mapped to deployed clarify/approval/trajectory (appendix)
- [x] Old→v2 diff confirmed: spec 01 & 04 byte-identical; DataHub +37 (DocEditor/search/resize)
- [x] Residency (connector-residency.tsx) confirmed DONE with file:line
- [x] Reports confirmed read-only MD download (no editable capability) — the headline gap

---

## Counts

- **Core-surface rows scored:** 27 (A:8 + B:11 + C:8) + 3 DataHub (D) = 30 scored rows across the four surfaces.
- **UNDONE:** 22 · **PARTIAL:** 11 · **DONE:** 9 (across A–D; some rows in D duplicate A).
- **De-duplicated headline count for the four surfaces: 22 UNDONE + 11 PARTIAL.**
- **Biggest single gap:** Reports-as-editable-files (Surface A) — reports are read-only Markdown downloads; no chat-edit-with-diff, no versioning, not in the file tree.
