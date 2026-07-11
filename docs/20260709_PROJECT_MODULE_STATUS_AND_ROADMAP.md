# BioMate Project Module — Current Status & Work Remaining

**Date:** 2026-07-09  
**Branch:** `integration/next-phase`  
**Commit:** `2aeaa3d` (feat: complete project module — Chat/Files/Workflow Runs workspace)

---

## What the Project Module Is

Projects give users a persistent workspace to organize related chats, uploaded data files, and workflow runs. A project has:

- A **name, description, and research goal** (instructions) that BioMate reads as context in every chat
- **Uploaded files** stored in S3 under the project's prefix
- **Linked chat sessions** — chats can be explicitly scoped to a project
- **Linked workflow runs** — every run executed within a project chat is tagged with `project_id`
- **A detail page** that surfaces all three in one workspace view

The design was informed by the **lcms-platform** open-source pattern (Upload → Analyze → Results) and the **biomate-connector** MCP surface (`biomate_session`, `list_runs`, `preview_file`).

---

## Architecture

### Database

```
memory_projects              — project metadata (name, description, researchGoal, primaryDomain, etc.)
  └── chat_sessions.project_id  (FK, ON DELETE SET NULL)
  └── execution_runs.project_id (FK stored in JSONB on execution_runs table)
```

### Backend Endpoints (`frontend/server/project-routes.ts`)

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/projects` | List all projects for the user |
| `POST` | `/api/projects` | Create a project |
| `GET` | `/api/projects/:id` | Get project detail |
| `PATCH` | `/api/projects/:id` | Update name/description/researchGoal/status |
| `POST` | `/api/projects/:id/archive` | Soft-delete (status → archived) |
| `DELETE` | `/api/projects/:id` | Hard-delete (cascades) |
| `GET` | `/api/projects/:id/sessions` | List chat sessions scoped to this project |
| `POST` | `/api/projects/:id/files/upload` | Upload a file to project S3 prefix |
| `GET` | `/api/projects/:id/files` | List project files (from S3 + DB) |
| `DELETE` | `/api/projects/:id/files/:fileId` | Delete a project file |
| `GET` | `/api/projects/:id/files/:fileId/url` | Presigned S3 download URL |
| `GET` | `/api/workflows/runs?projectId=:id` | List all workflow runs for a project |

### How Project Context Flows into Chat

1. User sets a project active (via sidebar link or project detail "Chat" button)
2. Active project ID stored in `localStorage['biomate-active-project-id']`
3. `chat-interface.tsx` reads it and includes `projectId` in every `/api/chat/stream` request body
4. Server links the `chat_sessions` row to the project via `project_id = COALESCE(..., ctx.projectId)`
5. `chat-with-artifacts.tsx` reads `activeProjectId` from `useActiveProject()` context and passes it to `executeWorkflow()`
6. `executeWorkflow` POSTs `projectId` to `/api/workflows/execute` → run is stored with `project_id`

### Active Project Banner

When any project is active, a thin banner appears at the top of the main chat area (`App.tsx: ActiveProjectBanner`):

- Shows project name (clickable → goes to project detail)
- "Go to project" link
- × button to clear the active project (chat reverts to project-less mode)

---

## What Is Built

### Project Detail Page (`frontend/client/src/pages/project-detail.tsx`)

Three-tab workspace:

**Chat tab**
- "New Chat" CTA card (dashed border, click anywhere or button) — sets project active in localStorage, navigates to `/` (main chat)
- Recent sessions list: title, message count, relative timestamp, click to open directly
- Refresh button to reload sessions from `/api/projects/:id/sessions`

**Files tab**
- `ProjectFileTree` component: drag-and-drop upload, folder tree view (inputs/ outputs/ reports/), download, delete
- On desktop: native OS file picker via `desktopPickAndUpload()`
- Pinned footer: "Analyze with BioMate →" button — activates project and opens chat
- File upload uploads to S3 via `/api/projects/:id/files/upload`

**Workflow Runs tab**
- Left panel: list of all runs linked to this project (fetched from `/api/workflows/runs?projectId=...`)
  - Status icons: green checkmark (completed), red X (failed), blue spinner (running), grey circle (idle)
  - Run name, relative timestamp
  - Click to select
- Right panel: full `NextflowWorkflowViewer` for the selected run
  - Phases, steps, QC gates, output files, findings, download report — exactly as in the main chat

Right sidebar (always visible):
- Editable instructions/research goal (inline edit → PATCH `/api/projects/:id`)
- Metadata: created date, chat count, run count, last updated

### Sidebar Integration (`frontend/client/src/components/app-sidebar.tsx`)

Projects section shows up to 12 active projects. Each project expands to show three quick-navigation links:
- **Chats** → `/projects?project=<id>&tab=chat`
- **Files** → `/projects?project=<id>&tab=files`
- **Workflows** → `/projects?project=<id>&tab=workflows`

### Create Project Dialog (`frontend/client/src/components/create-project-dialog.tsx`)

- Fields: name, description, research goal / instructions, category, tags
- On creation: fires `biomate:projects-updated` DOM event → sidebar refreshes automatically
- POSTs to `/api/memory/projects`

### Projects List Page (`frontend/client/src/pages/projects.tsx`)

- Grid of project cards with status badge, category, tags, progress
- Search filters API-loaded state (not localStorage)
- Sort by recent activity / date created / name
- Status filter: all / active / completed / archived

---

## What Is Left To Do

### 1. Project Context Injected into LLM Prompt

**Current state:** The `projectId` is stored on the chat session, but the LLM is not currently given the project's `researchGoal` as system context.

**What's needed:**
- When `projectId` is set on a stream request, the backend should load `memory_projects.researchGoal` and prepend it to the system prompt or inject it as a tool result
- File: `backend/lib/galaxy/ai/ai_assistant.py` — add project context loading in the stream handler
- This is the highest-value feature: BioMate would automatically "know" the project's background without the user re-explaining

### 2. Files → Chat Pre-fill

**Current state:** "Analyze with BioMate →" opens a blank new chat with the project active.

**Better UX (lcms-platform pattern):** After clicking Analyze, pre-fill the chat input with a message listing the uploaded files and suggesting next steps:

```
"I've uploaded these files to my project:
- inputs/sample1.fastq.gz (2.3 GB)  
- inputs/sample2.fastq.gz (2.1 GB)
Please suggest the right workflow and run it."
```

**What's needed:**
- `openChatWithProject()` in `project-detail.tsx` should optionally accept a `prefilledMessage` string
- Pass it as `?q=<encoded message>` in the URL (the `RootRoute` in `App.tsx` already handles `?q=` on load)
- `ProjectFileTree` should expose an `onFilesChanged(files: ProjectFile[])` callback so the parent can build the message from actual uploaded file names

### 3. Run Count and Chat Count on Project Cards

**Current state:** Project cards on the list page show name, description, tags, status — but no activity counts.

**What's needed:**
- `GET /api/projects` response should include `sessionCount` and `runCount` (add to the SQL query in `project-routes.ts`)
- Show them as small metadata chips on each card: `3 chats · 7 runs`

### 4. Project Status Lifecycle

**Current state:** Projects have `active / archived / completed` status but there's no way to change it from the UI.

**What's needed:**
- Add a "…" menu on the project detail header with: Rename, Mark complete, Archive, Delete
- Wire to `PATCH /api/projects/:id` (supports `status` field already) and `DELETE /api/projects/:id`

### 5. Project-Scoped Run History in Workflow Panel

**Current state:** The Workflows tab shows all runs for the project but the `NextflowWorkflowViewer` in the right panel doesn't know which project it's in — it can't link back.

**What's needed:**
- Add a "Go to project" chip inside `NextflowWorkflowViewer` when `projectId` is set as a prop
- This creates a navigation shortcut from run → project

### 6. E2E Tests for Project Module

No Playwright E2E tests cover the project detail workspace end-to-end. `project-files.e2e.ts` covers file upload/delete but not:

- Chat tab: create chat → session appears in list
- Workflow Runs tab: run a workflow in a project chat → it appears in the runs list → select it → viewer renders
- Instructions edit: save research goal → appears as context in next chat

**What's needed:** A new `project-workspace.e2e.ts` covering the full flow:
```
create project → upload file → click Analyze → BioMate runs a workflow
→ go back to project → Workflow Runs tab → select run → verify viewer shows correct status
```

### 7. Project Search and Tagging from Projects Page

**Current state:** Tags are set at creation time only. No way to add/remove tags after creation.

**What's needed:**
- Inline tag editor on project detail header (click to add/remove tags)
- Wire to `PATCH /api/projects/:id` (already supports `tags` field? — needs verification in project-routes.ts)

### 8. Project Sharing / Collaboration

**Not started.** Projects are currently single-user (ownership enforced by `user_id` FK). For lab/team use:
- Share a project read-only or read-write with other users
- `project_members` join table
- Server-side permission checks on all project endpoints

### 9. Project Templates

**Not started.** For common research workflows (RNA-seq project, GWAS project, drug discovery project), pre-populate the project with:
- A set of default research goal instructions
- Suggested workflows to run
- Example parameter values

---

## File Map

```
frontend/
├── client/src/
│   ├── pages/
│   │   ├── projects.tsx              # Project list page
│   │   └── project-detail.tsx        # Workspace: Chat / Files / Workflow Runs
│   ├── components/
│   │   ├── app-sidebar.tsx           # Sidebar: projects section + per-project links
│   │   ├── create-project-dialog.tsx # New project form
│   │   └── project-file-tree.tsx     # File upload/browse/delete component
│   └── contexts/
│       └── active-project-context.tsx # Global active project state + localStorage sync
├── server/
│   ├── project-routes.ts             # All /api/projects/* endpoints
│   └── project-framework-wiring.test.ts  # Source-level wiring tests
└── e2e/
    └── project-files.e2e.ts          # E2E: create project, upload files, delete files

App.tsx                               # ActiveProjectBanner + ProjectsRouter
```

---

## Priority Order

| Priority | Item | Effort |
|---|---|---|
| 🔴 High | Project context → LLM system prompt | 1 day |
| 🔴 High | Files → Chat pre-fill with file names | 0.5 day |
| 🟠 Medium | Run/chat counts on project cards | 0.5 day |
| 🟠 Medium | Project status lifecycle UI (rename/archive/delete) | 0.5 day |
| 🟡 Medium | E2E tests for workspace flow | 1 day |
| 🟡 Medium | Inline tag editing | 0.5 day |
| 🟢 Low | "Go to project" chip in workflow panel | 0.5 day |
| 🟢 Low | Project sharing / collaboration | 3-5 days |
| 🟢 Low | Project templates | 2 days |
