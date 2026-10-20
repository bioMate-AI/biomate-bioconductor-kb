# Dataset panel — spec-by-spec design-conformance audit (2026-10-20)

Authoritative design: `reference/claude_design/data_centroid_design_v2/spec/04 Files
and the dataset object.html` (prose spec) + `dataui/DataHub.jsx` (prototype).
Implementation: `frontend/client/src/pages/data-hub.tsx`,
`components/project-file-tree.tsx`, `components/datasets/dataset-object.tsx`,
`components/datasets/dataset-file-preview.tsx`.
Backend capability matrix: `docs/20261020_UI_REFINEMENT_TRACKER.md` (item 6).

Every discrepancy below is tagged **[BUILD]** (backed by a real endpoint — do now),
**[PARTIAL]** (backed but degrades), or **[FUTURE]** (no backend — comment out +
document). Per the user's call: implement BUILD confidently, comment out FUTURE and
record them as future work.

---

## A. File tree (spec §4.2) — `project-file-tree.tsx`

| # | Spec | Impl now | Verdict |
|---|------|----------|---------|
| T1 | Header ingest entry **"＋ Add"** — drop a file, paste a URL, or pull from a connected database; quality card before anything runs (§4.2.2, §4.6) | Button labelled **"Upload"** (file picker + drag-drop only); no URL / database route | **[BUILD]** rename to "＋ Add"; file upload exists; URL via `/api/datasets/import-url`; database = Connectors. Menu with the 3 routes. |
| T2 | Search box over the file list (prototype `FileTree` has it) | No search box | **[BUILD]** client-side filter by name. |
| T3 | **Version tag `v3`** on a file row — only where >1 version exists (§4.2.2) | No vtag | **[PARTIAL]** versions = note-log; show `vN` only when the versions endpoint reports >1. |
| T4 | Header states scope: "Uploads and run outputs in this project" | No scope hint | **[BUILD]** add the hint line. |
| T5 | Folder rows (chevron/icon/name/count); file rows (quality dot/mono name) | Present ✓ (dots match; folders are real project structure) | OK |

## B. Object header + "Open in" (spec §4.3.1) — `dataset-object.tsx`

| # | Spec | Impl now | Verdict |
|---|------|----------|---------|
| H1 | **Open in: Jupyter / RStudio / Plot viewer / Ask in chat**, offered by file type (VCF → bcftools/terminal) | None of the Open-in launchers | **[PARTIAL/FUTURE]** composable (presign → `/api/datasets/import-url` → `/api/interactive/launch`) but Jupyter/RStudio open on the session history, don't bind the file. Build "Ask in chat" + "Download" now; Open-in launchers = wire via staging OR comment+document (no single endpoint; no file-binding). |
| H2 | Export is **"Export for deposit"** inside *Where it came from* (§4.5.3) | **RO-Crate export button in the header** | **[BUILD]** relocate to the provenance tab, rename "Export for deposit". |
| H3 | (no "Run QC" in header; quality is passive) | "Run full QC" button in header | **[BUILD]** product extra — move out of the header (into quality section) or drop. |
| H4 | Version chip shows **`v3`** (current version number) | Chip shows a **count** ("N versions") | **[BUILD]** show `v{current}`. |
| H5 | "Ask in chat" | "Use in chat" | **[BUILD]** rename. |
| H6 | rows/cols/size/version live in the **stat grid below Preview**, not header | size + content-type badges in header | **[BUILD]** move to stat grid. |

## C. Tabs (spec §4.3–4.5)

| # | Spec | Impl now | Verdict |
|---|------|----------|---------|
| TB1 | Tabs: **Preview · Versions · Where it came from** | **Preview · Lineage · Versions** | **[BUILD]** rename "Lineage"→"Where it came from"; reorder. |
| TB2 | Quality lives in *Where it came from* (§4.5.2); identity in the stat grid | Quality + identity folded into **Preview** (long scroll) | **[BUILD]** move quality → provenance tab; identity → stat grid. |

## D. Preview tab (spec §4.3)

| # | Spec | Impl now | Verdict |
|---|------|----------|---------|
| P1 | Sub-view toggle **Table / Columns / Plot** | Flat table only | Table **[BUILD]**; toggle **[BUILD]** (shell). |
| P1a | **Columns**: per-column name, inferred type, % missing + bar, distinct count, watch chip | — | **[FUTURE]** profiler returns column NAMES + 8 sample rows only; no per-column stats. Comment out + document (needs backend). |
| P1b | **Plot**: distributions (library sizes/PCA/volcano); if nothing numeric, say so + offer Jupyter/chat | — | **[FUTURE]** no distribution/histogram data from backend. Ship the honest "nothing numeric — open in Jupyter or ask in chat" fallback (spec-sanctioned); real plots = future. |
| P2 | **Edit** → editable table, amber cells to fix, **saving writes a new version** (append-only), with the "saving writes v4…" copy | — | **[FUTURE]** no edit→content-version endpoint (POST versions appends a NOTE only). Comment out + document. |
| P3 | Table shows **quality-flagged cells amber** (the verdict's evidence) | plain cells | **[FUTURE]** per-cell flags not exposed by profiler. |
| P4 | **Stat grid** below preview: rows, columns, size, current version, domain summary | identity rows (Name/Size/Type/Reference) | **[BUILD]** render the stat grid from `profile.shape` + size + version. |

## E. Versions tab (spec §4.4)

| # | Spec | Impl now | Verdict |
|---|------|----------|---------|
| V1 | Rows: number, **what changed in words**, who + when, **used by N runs**; current marked | version/label/current/when/note/author | **[PARTIAL]** words = the note (synthesized v1 has none); "used by N runs" not available per-version. |
| V2 | **Compare** (cell/column diff) + **Restore** (as new version) | — | **[FUTURE]** no diff/restore endpoint. Comment out + document. |
| V3 | Manual "add note" box | present | spec has versions come from edits/runs, not a manual note. Keep but de-emphasize, or gate behind the (future) edit flow. |
| V4 | "Runs that read this file" list | under Lineage (consumers) | **[BUILD]** also surface in Versions per spec, from the consumers endpoint. |

## F. Where it came from tab (spec §4.5)

| # | Spec | Impl now | Verdict |
|---|------|----------|---------|
| W1 | Origin: type, label, who/when, note, **Open the run that produced it →** | produced-by run id/workflow/status; origin source/ref/added | **[PARTIAL]** show run **NAME** (not raw id) when tracked; "Open run" when runId present. |
| W2 | **Content hash** + dedup note | — | **[FUTURE]** not exposed. Document. |
| W3 | **Visibility** (this project / whole account) two-button control + consequence copy | — | **[FUTURE]** scope-promotion not wired in the object. Document. |
| W4 | **Quality at ingest** (verdict + notes + inheritance rule) lives HERE | currently in Preview | **[BUILD]** move the DataPerception panel here. |
| W5 | **What used it, and what came out** — consumers (status/version/gate) + produced outputs (typed, open as dataset objects) | consumers list only | consumers **[PARTIAL]**; produced-outputs **[FUTURE]** (not available). |
| W6 | **Export for deposit** (RO-Crate) | in header | **[BUILD]** move here. |

## G. Empty / failure states (spec §4.8)
Impl already renders honest empty states (no-files, no-consumers, no-versions,
no-preview, no-ref). Largely aligned — keep.

---

## Build plan (derived from the audit)

**Do now (BUILD):** T1 (＋ Add menu), T2 (search), T4 (scope hint); H2/H6 relocate
RO-Crate + stats, H4 `v{N}` chip, H5 "Ask in chat", H3 move Run-QC out of header;
TB1/TB2 rename+reorder tabs + move quality/identity; P1 Table + toggle shell, P1b
Plot honest-fallback, P4 stat grid; V4 runs-read list; W1 run name, W4 quality moved
here, W6 Export-for-deposit here. T3 vtag + V1 words = **PARTIAL** (show when data
present).

**Comment out + document as future work (FUTURE — no backend):** P1a Columns stats,
P2 Edit→new-version, P3 amber cells, V2 Compare/Restore, W2 content hash, W3
visibility control, W5 produced-outputs, and the Open-in Jupyter/RStudio launchers
until the one-call staging endpoint + file-binding exist (H1).

Future-work backend tickets this implies: (1) per-column profile stats + numeric
distributions in `/api/perception/profile`; (2) content-versioning + an edit-save
endpoint (copy-on-write); (3) a dataset→history staging endpoint for interactive
tools; (4) per-version consumer attribution + produced-outputs in lineage.
