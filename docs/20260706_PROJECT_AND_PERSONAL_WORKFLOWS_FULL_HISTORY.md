# BioMate — Projects & Personal Workflows: Full Feature History

**Date compiled:** 2026-07-06  
**Branch:** `integration/next-phase` (worktree: `workflow-upload-integration`)

This document covers everything built for the **Projects** subsystem and the **Personal Workflow upload/run** subsystem from inception to the current state.

---

## Feature Overview

| Feature | Status | Commits |
|---------|--------|---------|
| Project CRUD (create, list, detail, archive) | ✅ Complete | `4c793c21d`, `5078829fc`, `24a5ccb20` |
| Project research instructions (read/write) | ✅ Complete | `4c793c21d`, `b019690f1` |
| Project file tree (S3-backed) | ✅ Complete (S3 skipped locally) | `4c793c21d` |
| Personal workflow upload (.nf file) | ✅ Complete | `4c793c21d` |
| Personal workflow list (`GET /api/workflows/personal`) | ✅ Complete | `4c793c21d`, `7f0768b9f` |
| Personal workflow delete | ✅ Complete | `5078829fc`, `24a5ccb20` |
| Personal workflow execution (file_content path) | ✅ Complete + E2E | `c31b161f0` (current session fixes) |
| WorkflowHistoryDialog (Run History / My Imports / Import Workflow tabs) | ✅ Complete | `4c793c21d` |
| ConnectorsDialog (3-tab design) | ✅ Wired, button visible | `4c793c21d`, `5078829fc` |
| CreateProjectDialog (real API call) | ✅ Complete | `5078829fc`, `24a5ccb20` |
| Settings dialog — API Keys for MCP | ✅ Complete (this session) | current session |

---

## Phase 1: Core Infrastructure (`4c793c21d` — 2026-07-03)

**Commit:** `feat: workflow upload + project file tree + UX fixes`  
**Files changed:** 20 files, +1861 / -193 lines

### 1.1 Personal Workflow Upload

**Backend:**
- New DB table: `personal_workflows` — migration `0018_personal_workflows.sql`
  ```sql
  CREATE TABLE personal_workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    workflow_name TEXT NOT NULL,
    file_name TEXT,
    file_type TEXT DEFAULT 'nf',
    description TEXT,
    file_content TEXT,  -- stored in DB for small files
    s3_key TEXT,        -- for S3-backed storage
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
  );
  ```
- `POST /api/workflows/upload-file` — multipart upload accepting `.nf` or `.ga` files
  - Stores content in DB (`file_content`) for files under threshold
  - Stores to S3 via `s3-client.ts` for larger files
- `GET /api/workflows/personal` — list all personal workflows for current user
- `frontend/server/project-routes.ts` — new router for project CRUD endpoints:
  - `GET /api/projects`
  - `POST /api/projects`
  - `GET /api/projects/:id`
  - `PATCH /api/projects/:id`
  - `DELETE /api/projects/:id` (archive)
  - `GET /api/projects/:id/files` (S3 file tree)
  - `GET /api/projects/:id/files/download` (pre-signed URL)
  - `POST /api/projects/:id/files/upload` (S3 upload)

**Frontend — WorkflowHistoryDialog (major rewrite):**
- Three tabs with `data-testid` selectors:
  - `tab-run-history` — existing run history
  - `tab-my-imports` — user-uploaded personal workflows table
  - `tab-import-workflow` — upload form (file picker, name, description)
- Upload form:
  - File input (accepts `.nf`, `.ga`)
  - `workflowName` text field (required)
  - `description` textarea (optional)
  - Success state: "View in My Imports" button appears after successful upload
  - Error display for validation failures
- My Imports table:
  - Columns: Workflow Name, Type badge, Uploaded date
  - "Open" button → calls `onOpenRun` callback which loads the workflow into the right panel
  - "Delete" (trash icon) button → confirms, calls `DELETE /api/workflows/personal/:id`
  - `data-testid="button-delete-personal-${id}"` for E2E targeting
- `workflow-history-dialog.tsx` constructs a `workflowGa` object from the personal workflow:
  ```javascript
  const workflowGa = {
    name: full.workflow_name,
    workflow_type: 'nextflow',
    nextflow_path: `personal_workflow/${full.id}.nf`,
    personal_workflow_id: full.id,  // key for execution routing
    required_params, optional_params,  // parsed from .nf file
    parameters: {},
    steps: {},
    domain: 'user_import',
  };
  ```

**Frontend — App Sidebar (`app-sidebar.tsx`):**
- "Import Workflow" quick-access button always visible (opens WorkflowHistoryDialog to Import tab)
- Projects section always visible in sidebar (was previously conditional)
- "New project" button (`data-testid="button-new-project"`)
- Project list with clickable items navigating to `/projects/:id`

**Frontend — Other components:**
- `project-file-tree.tsx` — new 401-line component:
  - Renders S3 file tree for a project
  - Folder expand/collapse
  - File download via pre-signed URL
  - Upload drag-and-drop area
  - `data-testid="project-file-tree"`
- `parse-nf-params.ts` — Nextflow param extraction utility:
  - Parses `params {}` block from `.nf` file content
  - Returns `required_params` / `optional_params` arrays for the workflow panel
  - Handles DSL2 syntax
- `project-detail.tsx` — Project detail page with:
  - Research Instructions tab (PATCH `/api/projects/:id` to save)
  - Files tab (shows `ProjectFileTree` if S3 is configured)
- `connectors-dialog.tsx` — new 263-line ConnectorsDialog:
  - Tab: Scientific Databases (PubMed, UniProt, PDB, etc.)
  - Tab: AI & Platforms (OpenAI, Anthropic, Gemini, etc.)
  - Tab: Skills (Python, R, Nextflow, etc.)
- Auth fix: `setIsLoading(false)` in `login()` — fixed blank screen on first login
- Login page: mobile eye-button (show/hide password) enlarged to 44×44px (HIG compliant)
- S3 client: `s3-client.ts` updated with proper bucket/key path construction

**E2E — `workflow-upload.e2e.ts` (12/12 pass):**
Tests covering upload form, My Imports display, and error handling.

---

## Phase 2: G1–G3 Bug Fixes (`5078829fc`, `24a5ccb20` — 2026-07-04)

**Commits:**
- `feat: G1-G3 fixes + E2E proof — project API, workflow delete, connectors sidebar` (worktree)
- `feat: G1-G3 fixes — project API call, workflow delete endpoint, connectors button` (main branch reconciliation)

### G1 — CreateProjectDialog: real API call (not localStorage)

**Problem:** `CreateProjectDialog` was saving projects to localStorage instead of calling the backend.

**Fix (`create-project-dialog.tsx`):**
```javascript
// Before: localStorage.setItem('projects', ...)
// After:
const res = await fetch('/api/projects', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  credentials: 'include',
  body: JSON.stringify({ name, description }),
});
const project = await res.json();
// Navigate to /projects/:id
```

### G2 — Personal Workflow Delete endpoint + UI

**Problem:** No `DELETE /api/workflows/personal/:id` route existed; the trash button in My Imports had no backend.

**Fix (`routes.ts`):**
```javascript
app.delete("/api/workflows/personal/:id", authenticateToken, async (req, res) => {
  const result = await db.delete(personalWorkflows)
    .where(and(
      eq(personalWorkflows.id, req.params.id),
      eq(personalWorkflows.userId, String(req.user?.id))
    ))
    .returning({ id: personalWorkflows.id });
  if (result.length === 0) return res.status(404).json({ error: 'Not found' });
  res.json({ ok: true });
});
```

**Fix (`workflow-history-dialog.tsx`):**
- Added `deletingId` state to track which row is being deleted
- Trash button: `onClick` → confirm dialog → `DELETE` → remove from local state
- Row hides immediately on success (optimistic UI)

### G3 — Connectors sidebar button visible

**Problem:** The Connectors button in the sidebar was commented out pending review.

**Fix:** Uncommented the Connectors button in `app-sidebar.tsx`. `ConnectorsDialog` is now reachable from the sidebar.

**E2E coverage added (19/19 pass):**
- `project-create.e2e.ts`: auth gate, dialog open, real API call, list verification
- `workflow-delete.e2e.ts`: auth gate, delete removes row, 404 for unknown ID
- `connectors-dialog.e2e.ts`: button visible, dialog opens, all 3 tabs render

---

## Phase 3: Personal Workflow API Search + Flash thinking fix (`7f0768b9f` — 2026-07-03)

**Commit:** `fix: disable thinking tokens for Flash models; add search to personal workflows API`

### Personal workflow search

`GET /api/workflows/personal?search=<term>` added — ILIKE name filtering for the My Imports search input in the dialog.

### Flash thinking fix

Flash models with `thinkingBudget=-1` (dynamic) were spending 60s+ thinking on simple intent classification. Fixed to `thinking_budget=0` for Flash, keeping it on the fast (non-thinking) path.

---

## Phase 4: Project Files E2E (`b019690f1`, `f41bf63e8` — 2026-07-04)

**Commit:** `test: project-files E2E — 8/8 pass locally (S3 skipped), fixed tab selectors and port routing`

**File:** `frontend/e2e/project-files.e2e.ts` (311 lines, 12 tests)

Tests proven (8/12 pass locally; 4 skip without S3):
1. Auth gate — `GET /api/projects` → 401 when unauthenticated
2. Create project via dialog → navigates to detail page
3. Research instructions — save (PATCH) and verify persistence
4. Files tab renders — upload button present (even without S3)
5. Upload .nf workflow → success state → "View in My Imports"
6. My Imports row shows workflow name
7. "Open" button loads workflow into right panel
8. Delete workflow row → disappears

S3-dependent tests (skip without `S3_BUCKET` env):
- File tree renders with folders
- File download generates pre-signed URL
- Upload to S3 via drag-and-drop
- File tree refresh after upload

**Infra fixes in this commit:**
- `playwright.config.ts` — loads `.env.local` after `.env` for worktree port override
- `.env.local` — `PORT=5001` + `BIOMATE_URL=http://localhost:5001` (worktree-specific)
- Tab selector fixed: use `data-testid="tab-my-imports"` not `getByRole("tab", { name: /my imports/i })` (more reliable)
- Multipart field: server expects `workflowName` not `name`

---

## Phase 5: Full Researcher Journey E2E + Personal Workflow Execution (`c31b161f0` — 2026-07-04)

**Commit:** `test: researcher journey E2E (8 steps) + backend file_content support for user-uploaded workflows`

### Backend — Galaxy `NextflowExecuteRequest` with `file_content`

**File:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

Added `file_content: Optional[str]` to `NextflowExecuteRequest`. When set:
1. Content is written to `/tmp/biomate_user_nf/<user_id>/<sanitized_name>.nf`
2. `nextflow_path` is overridden to the temp file path
3. Executor forces `local` executor (not AWS Batch)
4. `params.clear()` — drops all user-supplied params to avoid Nextflow 25+ strict-mode error ("Parameter X not declared in config")

```python
if _nf_path_str.startswith("/tmp/biomate_user_nf/"):
    compute["executor"] = "local"
    params.pop("outdir", None)
    params.clear()
    log.info("[Nextflow] Personal workflow — forcing local executor, cleared all params")
```

### Node.js routes — `nextflow_path` fallback for personal workflows

**File:** `frontend/server/routes.ts`

```javascript
const personalFileContent = ...  // fetched from DB by personal_workflow_id
const _nfBody = JSON.stringify({
  nextflow_path: request.workflowDefinition.nextflow_path
    || (personalFileContent ? 'personal_workflow/main.nf' : ''),
  ...(personalFileContent ? { file_content: personalFileContent } : {}),
  ...
});
```

This satisfies Pydantic's `nextflow_path: str` (non-Optional) requirement even when the execution is backed by uploaded file content.

### E2E — Researcher Journey (`researcher-journey.e2e.ts`)

**14 sequential tests (30/30 pass — Chromium + Firefox) covering:**

| Step | Action | Assertion |
|------|--------|-----------|
| 1 | Create project via sidebar dialog | Project appears in sidebar |
| 2 | Navigate to project, write research instructions | PATCH API succeeds |
| 3 | Navigate away and back | Instructions persisted (API + UI) |
| 4 | Files tab | Upload button visible, empty state |
| 5 | Import .nf workflow via dialog | Success state, "View in My Imports" |
| 6 | Open workflow from My Imports | Right panel opens, `workflow-right-panel` visible |
| 7 | **Run imported workflow** | Status tracks: `idle → running → completed` |
| 8 | Cleanup | Delete workflow, archive project |
| Bulk 1 | Upload 3 workflows via API | All 3 created |
| Bulk 2 | Open My Imports | All 3 visible |
| Bulk 3 | Delete BulkA via UI | Row disappears; B+C remain |
| Bulk 4 | Delete BulkB via UI | Row disappears; C remains |
| Bulk 5 | Close + reopen dialog | Only C visible (reload test) |
| Bulk 6 | Delete BulkC via API | Cleanup |

---

## Phase 6: UI Polish + Error Sanitization (`d2d10e16b` — 2026-07-02)

Not directly project/workflow, but affects the workflow panel experience:

- **Workflow panel**: wf-chip status-aware (chip-ok/chip-run/chip-fail)
- **Error display**: `sanitizeErrorText()` strips stack frames, S3 paths, Nextflow branding
- **Results links**: "View results / Download all" only on completed runs
- **Phases tab**: empty state message (context-aware: failed vs. not-yet-run)
- **Run-again button**: not gated by unfilled required params on completed state
- **Footer**: single button per state (idle=Run, running=hidden, completed=Run again, failed=Restart)

---

## Phase 7: Mobile + Settings (this session — 2026-07-06)

Documented separately in `20260706_WORKFLOW_UPLOAD_SETTINGS_MOBILE_FIXES.md`.

---

## Architecture Summary

### Personal Workflow Execution Stack

```
User uploads .nf file
    │
    ▼
POST /api/workflows/upload-file (multipart)
    ├── file_content stored in personal_workflows.file_content (DB)
    └── large files → S3 (s3_key stored in DB)

User opens My Imports → clicks "Open"
    │
    ▼
WorkflowHistoryDialog builds workflowGa {
    personal_workflow_id: <uuid>,
    nextflow_path: "personal_workflow/<id>.nf",
    required_params: [...parsed from file],
    optional_params: [...parsed from file],
}
    │
    ▼
NextflowWorkflowViewer opens in right panel

User clicks "Confirm & Run"
    │
    ▼
POST /api/workflows/execute (routes.ts)
    ├── Fetches file_content FROM DB using personal_workflow_id
    └── Sends to Galaxy: { nextflow_path: "personal_workflow/main.nf", file_content: <content> }
        │
        ▼
        Galaxy /api/nextflow/execute (nextflow_executor.py)
            ├── Writes file_content → /tmp/biomate_user_nf/<user>/<name>.nf
            ├── Overrides nextflow_path to the temp path
            ├── Forces executor: local
            ├── Clears all params (avoids Nextflow 25+ strict-mode error)
            └── Spawns nextflow run <temp_path>
```

### Project Data Flow

```
Sidebar "New project" → CreateProjectDialog
    │
    ▼
POST /api/projects → projects table (PostgreSQL)
    │
    ▼
Navigate to /projects/:id
    │
    ├── Research Instructions tab
    │       └── PATCH /api/projects/:id (saves instructions text)
    │
    └── Files tab
            └── GET /api/projects/:id/files (S3 listing)
                    └── ProjectFileTree renders folder/file tree
```

---

## Key Data-testid Reference

| Component | testid | Purpose |
|-----------|--------|---------|
| Sidebar | `button-new-project` | Open CreateProjectDialog |
| Sidebar | `button-import-workflow` | Open WorkflowHistoryDialog |
| Sidebar | `button-settings-sidebar` | Open Settings (API Keys) |
| WorkflowHistoryDialog | `tab-my-imports` | My Imports tab |
| WorkflowHistoryDialog | `tab-import-workflow` | Import/upload tab |
| WorkflowHistoryDialog | `button-delete-personal-${id}` | Delete personal workflow |
| WorkflowHistoryDialog | `button-view-in-my-imports` | Post-upload navigation |
| Workflow panel | `workflow-right-panel` | Right panel container |
| Workflow panel | `panel-overall-badge` | Run status badge |
| Workflow panel | `button-run-workflow-panel` | Run / Confirm & Run button |
| Workflow panel | `panel-run-again-cta` | Run again (completed state) |
| Settings | `tab-api-keys` | API Keys tab |
| Settings | `tab-content-api-keys` | API Keys tab content |
| Settings | `button-create-api-key` | Generate key button |
| Settings | `input-fresh-api-key` | New key display (shown once) |
| Settings | `api-keys-list` | List of all keys |
| Settings | `api-key-row-${id}` | Individual key row |
| Settings | `button-revoke-api-key-${id}` | Revoke button |
| Run Manager | `button-toggle-run-manager` | Open/close Run Manager |
| Run Manager | `run-manager-panel` | Panel container |
| Run Manager | `run-manager-scope-toggle` | Current chat / All chats |
