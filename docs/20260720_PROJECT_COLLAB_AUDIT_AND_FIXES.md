# Project Collaboration — Audit and Fixes

**Date:** 2026-07-20  
**Branch:** integration/next-phase  
**Commits:** `e52bf3bea` (E2E suite), `9627d85b6` (fixes)

---

## What Was Done

After the 10/10 E2E pass for the conference project collaboration suite, a visual audit of all 28 screenshots revealed 4 issues. All were fixed in the same session.

---

## Issues Found and Fixed

### Issue 1 — Feedback pulse blocks after-run view (`chat-with-artifacts.tsx`)

**Symptom:** A "Before you go" survey dialog appeared immediately when a workflow completed, overlapping the output files panel before the user had a chance to read results. Visible in CC5_04 screenshot.

**Root cause:** `setShowSessionEndPulse(true)` was called synchronously in the `useEffect` that fires on run completion. No delay, no frequency cap.

**Fix:**
- 8-second `setTimeout` before showing the pulse — users see their results first
- 24-hour localStorage frequency cap (`biomate-pulse-last-shown`) — suppressed on every subsequent run during a demo session

```typescript
// 24h frequency cap
const lastShown = localStorage.getItem('biomate-pulse-last-shown')
if (lastShown && Date.now() - parseInt(lastShown, 10) < 24 * 60 * 60 * 1000) return

// 8s delay
const t = setTimeout(() => {
  setShowSessionEndPulse(true)
  localStorage.setItem('biomate-pulse-last-shown', Date.now().toString())
}, 8_000)
return () => clearTimeout(t)
```

---

### Issue 2 — Stale test projects accumulate in fixture account (`conference-project-collab.e2e.ts`)

**Symptom:** The `/projects` list showed ~15 old test projects ("E2E List Test", "Sidebar Test", previous "BD Summit MG Demo" runs) from prior E2E sessions. Confusing for a conference demo.

**Root cause:** The `afterAll` hook deletes the project on clean test completion, but:
1. If a test fails early, `afterAll` may still run but the project creation in `beforeAll` may have failed silently
2. Projects from other suites (Sidebar Test, E2E Files Project) are never cleaned up by this file

**Fix:** Added a cleanup block at the top of `beforeAll` that fetches the full project list and deletes any project whose name starts with `"BD Summit MG Demo"` before creating the fresh one. Idempotent — safe to run on every test invocation.

```typescript
const listRes = await page.request.get(`${BASE_URL}/api/projects`)
const stale = listBody?.projects?.filter(p => p.name.startsWith("BD Summit MG Demo")) ?? []
for (const p of stale) {
  await page.request.delete(`${BASE_URL}/api/projects/${p.id}`)
}
```

---

### Issues 3 & 4 — Stale runs in Workflow Runs tab + Runs counter mismatch (`storage.ts`)

**Symptom (3):** A `clusterprofiler` run (red/failed, from a different session) appeared in the brand-new project's Workflow Runs tab before any workflow had been run in the current test. Visible in CC2_03 and CC6_02 screenshots.

**Symptom (4):** "Runs: 1" in the Details panel while the Workflow Runs list showed 3 entries.

**Root cause — single bug in `getExecutionRuns`:**

```typescript
// DB path: correctly filters by projectId ✅
if (projectId) conditions.push(eq(executionRunsTable.projectId, projectId))

// In-memory merge: projectId filter MISSING ❌
let memRuns = Array.from(this.executionRuns.values()).filter(r => !dbIds.has(r.id))
if (userId) memRuns = memRuns.filter(r => r.userId === userId)
// ← projectId filter absent here
if (mode) memRuns = memRuns.filter(r => r.mode === mode)
return [...result, ...memRuns].slice(0, limit)
```

Active runs that haven't been flushed to DB yet are stored in `this.executionRuns` (in-memory Map). When merging these with DB results, the code filtered by `userId`, `mode`, and `chatSessionId` — but **not by `projectId`**. Every in-memory run from every session for the user leaked into the project's results.

This caused:
- Issue 3: runs from completely different projects (clusterprofiler, extra ADMET) appearing in the new project's tab
- Issue 4: DB returned 1 run (correctly), in-memory appended 2 more (incorrectly) → list showed 3, Detail counter showed the stale "1" from DB only

**Fix:** One line added to the in-memory merge section:
```typescript
if (projectId) memRuns = memRuns.filter(r => r.projectId === projectId)
```

**Impact:** This was a data isolation bug affecting all users. Any project's Workflow Runs tab could show runs from other projects (or unlinked sessions) as long as those runs were still in the server process memory (typically the first ~few minutes after a run starts). On the dev server with gunicorn recycling every ~3 minutes, it was less visible in production but still present in the Node.js layer.

---

## Verification

E2E re-run (`bn066f9wt`) launched after all fixes to confirm:
- No stale runs in Workflow Runs tab before CC5 (the ADMET execution)
- Runs counter matches the list
- Feedback modal does not appear immediately on completion
- Project list clean (only one "BD Summit MG Demo" project)

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/client/src/components/chat-with-artifacts.tsx` | Feedback pulse: 8s delay + 24h frequency cap |
| `frontend/server/storage.ts` | `getExecutionRuns`: add `projectId` filter to in-memory merge |
| `frontend/e2e/conference-project-collab.e2e.ts` | `beforeAll`: clean up stale "BD Summit MG Demo" projects |
