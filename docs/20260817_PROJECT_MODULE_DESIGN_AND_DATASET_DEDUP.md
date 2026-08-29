# Project module — current design + dataset-deduplication proposal

**Date:** 2026-08-17
**For:** claude-design review & refinement (+ internal). Companion to `20260817_DATA_MANAGEMENT_FINDINGS.md` (the problem) and `20260817_RESOURCE_STRUCTURE_DESIGN_BRIEF.md` Part 2 (the data-centric design ask).
**Purpose:** (A) describe the current project module as it exists, and (B) propose how to resolve *"the same input file has many duplicate access points"* — the core data-management finding.

---

## Part A — Current project-module design (as built)

### What a project is (user-facing)
A **project** is a container that groups a user's **Chats**, **Files**, and **Workflows/Runs**, with a name, description, free-text **instructions** (background context applied to every analysis in the project), a status (active/archived/completed), **members with roles**, and a **share link**. In the sidebar, each project expands to **Chats / Files / Workflows**; a project-detail page shows the same.

### Components
- `projects.tsx` (list), `project-detail.tsx` (detail), `project-file-tree.tsx` (Files tab), `create-project-dialog.tsx`, `join-project.tsx` (invite acceptance), `project-notes.tsx`. Sidebar Projects section in `app-sidebar.tsx`.

### Data model (`frontend/shared/schema.ts`)
- **`Project`** = `{ id, name, description, instructions, status, chatSessions[] (session ids), documents[] (ProjectDocument[]), category, tags, progress, createdAt, updatedAt, lastActivity }`.
- **`ProjectDocument`** = `{ id, name, type: file|text|url|notes_synthesis, content (file path), url, size, format, uploadedAt, description }` — this is how an **input file** lives inside a project.
- **`outputDataset`** (separate schema) = `{ id, invocationId, ... }` — how a **workflow-produced** file is tracked; linked to a run/invocation, **not** to a ProjectDocument.
- **Galaxy HDA** — a file is materialized into a Galaxy history dataset **on demand** (`POST /api/projects/:id/files/:fileId/ensure-hda`) when a workflow needs it — a *third* representation.

### API surface (`frontend/server/project-routes.ts`)
CRUD (`/api/projects`, `:id`, archive, delete); **files** (`:id/files`, delete/patch a file, `:fileId/url` download, `:fileId/ensure-hda` Galaxy materialization); **sessions** (`:id/sessions`); **members** (`:id/members`, add/remove/patch-role, `members/me` leave); **share-link** (get/create/delete). Ownership + role checks enforced server-side (Owner/Editor/Viewer).

### Roles
**Owner** (full), **Editor** (run workflows, modify files), **Viewer** (read-only). Shared projects show a badge in the sidebar.

---

## Part B — The problem: one input file, many duplicate access points

The **same file** is represented by up to **four objects that share no identity**:

| Representation | Where | Model |
|---|---|---|
| Project file | Files tab | `ProjectDocument` in `project.documents[]` |
| Chat attachment | a chat message | a `dataset-attachment` chip (its own client state) |
| Galaxy dataset | workflow execution | a Galaxy **HDA** (created on demand by `ensure-hda`) |
| Run output | a completed run | an `outputDataset` (keyed by `invocationId`) |

Because none of these carry a **canonical dataset id**:
- **Re-uploading the same bytes creates a brand-new object** every time — no deduplication.
- The **same file** attached in chat, listed in Files, materialized as an HDA, and produced by a run are **four unlinked records** — the user can't move between them ("which runs used this file?" is unanswerable).
- **No lineage**: input → run → output → next-input links exist implicitly (a run knows its inputs/outputs) but there is no shared key to traverse them.

This is a **data-model** gap, not only a UI gap: there is no single "dataset" the surfaces can all point at.

---

## Part C — Proposed resolution: a canonical `Dataset` object (content-hash identity)

**Give every file one identity, computed from its content, and make every access point a *reference* to it — never a copy.**

### 1. Canonical id = content hash
On **every** ingest path (chat upload, project upload, URL import, public-repo fetch, and workflow output), compute a content hash (SHA-256 of bytes; for large S3 objects, a hash of the multipart ETag + size). That hash **is** the `dataset_id`.

### 2. One `datasets` registry
A single record per distinct content:
```
Dataset {
  dataset_id            // = content hash (stable, dedup key)
  name, size, format
  s3_uri                // single physical location
  scope                 // account-scoped; referenced by projects (not copied)
  origin                // uploaded | url | geo/sra/ena | run_output
  producing_run_id?     // set when origin = run_output  → enables lineage
  created_at
}
```

### 3. Every representation becomes a reference
- `ProjectDocument.dataset_id` → the canonical dataset (Files tab renders the dataset).
- Chat attachment → carries `dataset_id` (chip and Files show the *same* object).
- Galaxy HDA ↔ `dataset_id` mapping so `ensure-hda` is **idempotent** (one HDA per dataset per history, reused).
- `outputDataset.dataset_id` → so a produced file is a first-class dataset, reusable as an input.

### 4. What this buys (directly closes the findings)
- **Deduplication:** re-uploading identical bytes resolves to the existing `dataset_id` — the UI says *"already in your data — reuse it?"* instead of making a duplicate.
- **One object, many views:** chat chip, Files row, HDA, and run output all resolve to the same `dataset_id`, so the surfaces can cross-link (the "which runs used this?" / "what did it produce?" navigation).
- **Lineage for free:** runs record input `dataset_id`s and outputs record `producing_run_id` → the `input → run → output → next-input` graph is derivable (the lineage view the design brief Part 2 asks for), exportable for a data deposit.
- **Cross-project reuse:** a dataset is account-scoped; using it in another project is just referencing the same `dataset_id` — no re-upload.

### 5. Rollout (additive, low-risk)
- Add a nullable `dataset_id` to `ProjectDocument` / attachments / `outputDataset` and the HDA mapping; introduce the `datasets` registry.
- Compute the hash at each ingest point; **backfill** existing files by hashing them once.
- Dedup applies to new ingests immediately; historical duplicates get linked as they're re-touched. No surface breaks — each just resolves its `dataset_id` and can start cross-linking.

---

## Part D — What we'd like claude-design to review / refine
1. **Project IA:** should the **Files** tab become **dataset-centric** (each row a dataset object with lineage/runs), or should there be a distinct **"Data"** surface separate from raw Files? (Ties to the "data centroid" question in the design brief Part 2.)
2. **Dedup UX:** the moment a user re-adds an existing file — what does *"already in your data — reuse it?"* look like, in chat and in the Files tab, without friction?
3. **One dataset, many entry points:** design how a single dataset object presents consistently across the chat chip, the Files tab, an input-mapping slot, and a run output — so it reads as *the same thing* everywhere.
4. **Lineage surface:** where the input→run→output graph lives (a dataset detail view? an overlay on the run panel?) and how a bench scientist reads it.
5. **Scope & sharing:** how account-scoped datasets surface within projects and shared projects (roles from Part A) without implying a copy per project.
