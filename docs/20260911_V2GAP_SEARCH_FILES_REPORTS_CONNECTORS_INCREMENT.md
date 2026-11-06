# V2 Gap Increment — Reports-as-editable-files + Search-answer transparency

**Date:** 2026-09-11
**Branch:** `v2gap-search-files-reports` (off `integration/dev-test`)
**Gap doc:** `docs/20260909_V2GAP_SEARCH_FILES_REPORTS_CONNECTORS.md`
**Scope:** Highest-value, cleanly-testable slices of the four v2 surfaces. Full
builds (report versioning/chat-diff DocEditor; Connectors full page) deferred
with notes below.

---

## Implemented

### Surface A — Reports as editable files (Spec 12), scoped increment · P1

**File:** `frontend/client/src/v2/AfterRunReport.tsx` (`MethodsTab`)

The after-run **Methods report** is now an editable object rather than a
read-only `<pre>`. The tab defaults to the read-only report with an **Edit**
toggle; clicking Edit opens the report content in the existing, proven TipTap
document editor (`RegulatoryDocumentEditor`) — the same machinery the IND §2.6
surface uses. The user can revise the AI-generated methods prose and **Save an
edited version** (downloaded as markdown), then **Done editing** to return to
the read-only view.

- Reuses `RegulatoryDocumentEditor` (TipTap StarterKit + Highlight + CharacterCount).
- `recordEditPairs={false}` — a methods report is NOT IND §2.6 assembly, so it
  must not emit DPO feedback pairs to the regulatory training endpoint.
- Read-only remains the default; the editor mounts only on demand.

**testids:** `methods-tab`, `methods-readonly`, `methods-edit-toggle`,
`methods-editor`, `methods-save-edited`, `methods-done-editing`,
`methods-save-toast`.

**Tests:** `frontend/client/src/v2/AfterRunReport.test.tsx` — 5 new cases
(tab appears on non-stub report; read-only default; Edit opens editor + swaps
out `<pre>`; Save triggers a markdown download + confirmation toast; Done
returns to read-only). Verified behavior-coupled (break → fail).

### Surface B — Search-answer retrieval transparency (Spec 09) · P1

**File:** `frontend/client/src/components/citation-panel.tsx`

Added a **"How this was searched"** section (Spec 09 anatomy): one row per
source with `found · kept` counts, a proportional bar, and a `N of M kept`
summary chip. New optional prop `retrieval?: RetrievalSource[]`
(`{ name, found, kept }`) drives it.

Honesty contract (matches the existing `conflicts` prop pattern):
- renders ONLY when the retrieval path supplies real per-source counts;
- absent/empty → the section is omitted entirely (no fabricated "kept"
  derived from the citation list);
- the summary is the sum of the per-source counts;
- malformed rows (missing name / non-finite counts) are dropped.

**testids:** `retrieval-transparency`, `retrieval-summary`,
`retrieval-source-<name>`.

**Tests:** `frontend/client/src/components/citation-panel.retrieval.test.tsx`
— 6 new cases (rows render; per-source counts; summary sum; honest-empty when
omitted; honest-empty when `[]`; malformed rows dropped). Verified
behavior-coupled (breaking the guard fails 4/6; the 2 honest-empty cases
correctly still pass).

---

## Deferred (with reasons)

### Surface A — full Spec 12 (report versioning / chat-diff / report-in-file-tree / multi-format) — TOO LARGE

Not built. The full v2 thesis needs:
- server-side `fileVersions(id)` truth and a report-version-append endpoint —
  **no such backend endpoint exists**; a version chip would be fabricated;
- chat-propose-diff (NOW / PROPOSED / accept-reject → new version);
- the report appearing as an object in the project file tree
  (`project-file-tree.tsx` has no `report` source);
- PDF/DOCX/HTML/ZIP export (explicit "Future: DOCX/PDF generator" note already
  in the codebase).

The edit-and-save increment above delivers the hand-editing affordance without
fabricating persistence: the edited version is a local markdown download, not a
persisted server-side new version. Versioning is deferred honestly.

### Surface B — wiring `retrieval` from a live source — NO DATA SOURCE YET

The `retrieval` prop is spec-ready but **not wired from a caller**, for the
same reason the already-shipped `conflicts` prop is not wired:
`workflow-artifact.tsx` (the only `CitationPanel` caller) receives `citations`
with no per-source found/kept counts, and no backend endpoint supplies
retrieval statistics. Wiring it would require fabricating counts — forbidden.
When the retrieval path emits per-source `found`/`kept`, pass it straight
through; the UI is ready.

Also deferred from Surface B (not started): editable filter chips that
re-derive, "what was dropped and why", claim-level lead labels, inline ref-card
expansion under the claim, Boundary section, the study/system/finding/strength
disagreement table, and the two "what to do next" exits (turn-into-a-run /
save-as-editable-doc). These cross-depend on the Instant-lane answer surface
(a new route/component) and on Surface A's editable-file object.

### Surface C — Connectors full page + Skills tab + MCP — GATED / DEFERRED

Not changed. The Skills tab is built-but-dark because `/api/skills` proxies to
the Galaxy backend and the in-code comment states it returns 0 entries
(`connectors-dialog.tsx:65,524-525,626`). This is a **backend-data** question
that cannot be verified offline (no live backend in this worktree, and the
disk/no-Batch constraints forbid standing one up). Enabling the tab blind would
ship an empty/loading surface — a poor honest state. The full-page re-host and
the MCP-servers kind + Add-with-preview flow are larger structural builds left
for a dedicated pass. Residency remains DONE (already shipped).

---

## Verification

- `cd frontend && npx tsc --noEmit -p .` → **exit 0** (clean; baseline also clean).
- Touched + neighbouring suites (`vitest run`): **53 passed / 53**
  - `v2/AfterRunReport.test.tsx` (17, incl. 5 new)
  - `citation-panel.retrieval.test.tsx` (6, new)
  - `citation-panel.conflict.test.tsx` (5), `.evidence` (4), `.save-notes` (2)
  - `regulatory-document-editor.test.tsx` (5), `connectors-dialog.test.tsx` (14)
- No Nextflow / Batch runs; no artifacts generated. `frontend/node_modules`
  symlinked from `/Users/kky/biomate-review/frontend/node_modules` (disk-tight).
