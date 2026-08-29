# Data management & dataset-access — findings

**Date:** 2026-08-17
**Why this doc exists:** the data-centric problems were summarized verbally and folded (in stripped form) into the claude-design brief (`docs/20260817_RESOURCE_STRUCTURE_DESIGN_BRIEF.md`, Part 2), but the *detailed* findings were never written to their own document. This is that document — internal, with the real mechanisms and component/registry references (the design brief intentionally omits them). Companion to the failure-UX findings (`docs/20260817_FAILURE_UX_FINDINGS_AND_PLAN.md`).

---

## 1. The same dataset is accessed from many disconnected places, with no shared identity — **CORE ISSUE**

A single dataset that a user uploads or produces appears across **at least five surfaces**, each a different component with a different visual language, and **none of them share a dataset identity or state**:

| Surface | Component | What it shows the dataset as |
|---|---|---|
| Chat attachment chips | `dataset-attachment.tsx` (typed input/output) | a small chip on a message |
| Upload / dataset browser | `file-upload.tsx`, `dataset-dialog.tsx`, `galaxy-dataset-browser.tsx` | a row in a picker (local / URL / public GEO-SRA-ENA) |
| Input mapping | `dataset-validation-dialog.tsx` | a mapping to a workflow slot (confidence high/med/low + reasoning) |
| Project files | `project-file-tree.tsx` (Projects → Files) | a file in a tree |
| Run outputs / previews | `step-output-preview.tsx`, `chat-output-attachments.tsx`, `workflow-artifact.tsx` (Outputs tab) | a per-step output file / a report row |

**The problem:** there is no canonical "dataset object." The same file is re-represented five times, and the user cannot move between representations — e.g. from a chat chip to "which runs used this file" to "what did they produce." Each surface is a dead end.

## 2. No data centroid / no lineage view

There is no single view answering *"what is this dataset, where did it come from, which runs consumed it, and what did they produce?"* Provenance data **is captured** (the run audit log records inputs, params, tool versions, outputs), but it is not exposed as a **navigable, data-first** surface — it's buried per-run. So the dataset is never the center of anything; the *run* is.

## 3. Input → output is not a graph

"Reuse a prior output as the next input" works functionally (there is a `resume_from_run_id` / reuse-prior-output path), but the user cannot **see** the `input → run → output → next-input` chain. The lineage that would make a data-centric tool feel coherent is invisible, even though the underlying links exist in run records.

## 4. Dataset scope, identity & deduplication are unclear

- **Scope ambiguity:** is a dataset owned by a *chat session*, a *project*, or the *account*? It surfaces in all three (chat chips, project Files, re-use across sessions) but there's no explicit model the user sees.
- **No identity / dedup:** the same file uploaded twice (or produced by two runs) is two unrelated objects. There's no content hash / "this is the same dataset" notion, so re-uploads and derived copies proliferate with no linkage.
- **Cross-project reuse:** unclear whether/how a dataset in one project can be used in another without re-uploading.

## 5. Data-*source* fragmentation (related but distinct) — verify before acting

Separate from the *user's* datasets: BioMate's **data sources** (the databases/repositories it can pull from) are fragmented across **three siloed registries** — roughly **30 Galaxy sources + 20 federation sources + 14 MCP sources (~60+)** — and the chat/generation path historically saw only ~20 of them. The fix direction is **one source registry that every surface (chat, workflow generation, connectors) reads from**. *(This is from prior analysis / memory `project_data_source_fragmentation`; re-verify the current counts and which registry each surface reads before implementing — I under/over-count these from memory.)*

## 6. Ingest entry point is a native OS file picker

The upload affordance (paperclip) opens the operating system's native file dialog rather than an in-app panel, so the described in-app **"Local upload" data card + QC badge** is not a first-class BioMate surface at ingest time — the instant data card appears after, not as part of a coherent ingest → data-object flow. (Observed while capturing UI screenshots, 2026-08-17.)

## 7. Cross-cutting consequence

Because data is scattered and identity-less, everything data-centric is weak: no "my data" home, no lineage, no dedup, no cross-run/-project continuity, and provenance that exists in the backend never becomes a user-facing story. This is the gap the claude-design brief Part 2 asks design to solve, and it is also an information-architecture/backend-model gap (a canonical dataset object + a source registry), not only a UI gap.

---

## Remediation directions (for planning — not yet scheduled)

1. **A canonical dataset object** (backend + shared client model): stable id, content hash for dedup, scope (account/project), and links to the runs that consumed/produced it. Every surface renders *this* object instead of re-representing the file.
2. **A data centroid surface** (design in progress via claude-design): a dataset as a first-class entity with Overview/QC · Lineage · Runs · Derived-outputs — or an inline lineage graph. See the design brief Part 2.
3. **Lineage graph** built from the run records we already store (input → run → output → next input); exportable for a data deposit (GEO/PRIDE/EMDB).
4. **One source registry** all surfaces generate from (Finding 5), replacing the three siloed registries so chat sees the full source set.
5. **Dedup & scope model**: content-hash identity so re-uploads/derived copies link to one dataset; explicit account/project scoping surfaced in the UI.

## Relationship to the other 2026-08-17 docs
- `20260817_RESOURCE_STRUCTURE_DESIGN_BRIEF.md` — the *design-facing*, self-contained ask (Part 1 capability legibility, Part 2 data-centric UI). This doc is the *internal, detailed* backing for Part 2.
- `20260817_FAILURE_UX_FINDINGS_AND_PLAN.md` — the separate failure-handling defects (leak, useless-restart, progress-as-messages).
- `20260817_data_ui_screenshots/` — the current-UI screenshots referenced above.
