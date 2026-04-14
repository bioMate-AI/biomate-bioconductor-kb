# Session 6 — Production Hardening & Pilot Launch
**Date:** 2026-04-13  
**Branch:** integration/next-phase → stronger_backend  
**Goal:** Make the platform ready for the first real-user pilot cohort

---

## Context

Sessions 1–5 delivered:
- S1: Website personalization
- S2: UX surfaces (upload, phase controls, inline viz)
- S3: UX intelligence (right panel, pre-exec summary, findings card)
- S4: MCP server, instrument connectors, WeChat/Open Claw
- S5: Benchmarking, autofix, SimulatedUser E2E

The platform now has all major features. Session 6 closes the remaining gap between
"works in dev" and "reliable for external pilots". Three tracks, all independent —
can be parallelised.

---

## Track 6A — AWS Output Delivery (High Priority)

### Problem
`FindingsCard` and `ChatOutputAttachments` both work by reading local disk at
`/tmp/nextflow_runs/<runId>/output/`. When a workflow runs on **AWS Batch**, outputs
land in S3 (`s3://biomate-nextflow-work/<runId>/`), not on the local server disk.
The output viewer silently shows nothing.

### What to build

**6A-1 — S3 output manifest on completion** (`nextflow_executor.py`)  
When a Batch run reaches terminal state, scan the output S3 prefix and write
`output/s3_manifest.json` (array of `{name, s3_key, size, content_type}`).
Also download small text/JSON files (<500 KB) to local cache for the viewer.

**6A-2 — S3-aware outputs endpoint** (`routes.ts`)  
`GET /api/workflows/runs/:id/outputs`: if `NEXTFLOW_USE_AWS=true` and local dir
is empty, fall through to S3 manifest. Return `{source: 's3', files: [...]}` with
presigned download URLs (1-hour TTL via `aws s3 presign`).

**6A-3 — S3-aware findings endpoint** (`routes.ts` + `nextflow_executor.py`)  
`GET /api/workflows/runs/:id/findings`: if no local `findings_data.json`, check
`s3://biomate-nextflow-work/<runId>/output/findings_data.json`. If found, stream
it from S3 instead of triggering re-analysis.

**6A-4 — Download commands presigning** (`routes.ts`)  
`GET /api/workflows/runs/:id/download_commands`: current implementation returns
`aws s3 cp` CLI commands. Add presigned URL array for browser-native download
(no CLI needed for pilot users who don't have AWS credentials).

### Files
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
- `frontend/server/routes.ts`
- `frontend/client/src/components/chat-output-attachments.tsx`

### DoD
- E2E: launch an ADMET run on AWS Batch, assert output files visible in viewer
- Output files link as presigned URLs (HTTP GET, no auth required)
- `findings_data.json` loaded from S3 for completed Batch runs

---

## Track 6B — Memory P2: Cross-Session Context Injection (Medium Priority)

### Problem
P1 fixed session memory persistence to DB. P2 is still open: memories from past
sessions are stored but never **injected** into new conversations. A returning
pilot user who ran ADMET on their compound last week gets no continuity — the
system treats them as new every time.

### What to build

**6B-1 — pgvector embeddings for session memories** (`backend/lib/galaxy/`)  
When `SessionMemoryUpdater` writes a memory entry, also compute an embedding
(Claude `text-embedding-3-small` or `sentence-transformers/all-MiniLM-L6-v2`)
and store in a `session_memory_embeddings` Postgres table with a `pgvector`
column.

**6B-2 — Retrieval at conversation start** (`galaxy-assistant.ts`)  
At the start of each new conversation, query top-K (k=5) most relevant memories
by cosine similarity to the user's first message. Inject them as a system
context block before the main system prompt:
```
[Past session context]
- 2026-04-10: Ran ADMET for compound CC(=O)Nc1ccc(O)cc1 → completed, ΔGbind -7.2 kcal/mol
- 2026-04-09: Asked about KRAS G12C inhibitors → pocket detection workflow run
```

**6B-3 — Memory UI panel** (optional, if time)  
`client/src/components/memory-panel.tsx`: collapsible panel in the sidebar showing
the user's stored memories (recent sessions, preferences, past results). Allows
manual deletion.

### Files
- `backend/lib/galaxy/ai/session_memory.py`
- `backend/lib/galaxy/model/` (new `session_memory_embeddings` table)
- `frontend/server/galaxy-assistant.ts`
- `frontend/server/routes.ts` (GET /api/memory, DELETE /api/memory/:id)

### DoD
- New conversation for returning user includes relevant past session context
- Memory retrieval adds <200 ms to first response latency
- E2E: two-session test — run workflow, start new session, assert past context appears

---

## Track 6C — Pilot Onboarding Polish (Medium Priority)

### Problem
The current new-user experience is:
1. Register → blank chat interface
2. No guidance on what to type
3. No example workflows visible until first message sent
4. Survey dialog appears immediately (jarring)

Pilot users (PIs, postdocs) need to reach their first successful workflow run in
<5 minutes with zero hand-holding.

### What to build

**6C-1 — Guided first-run experience** (`client/src/components/`)  
For users with 0 messages: show a domain picker (`genomics | drug_discovery |
cryo_em | proteomics | single_cell`) and 3 suggested starter prompts per domain.
Clicking a prompt sends it directly. Disappears after first message.

**6C-2 — Survey timing fix** (`post-run-micro-survey.tsx`)  
Move the post-run survey trigger from "after workflow panel appears" to "after
workflow reaches terminal state" (completed/failed). Add a 3-second delay and a
"Not now" button that suppresses for 7 days.

**6C-3 — Onboarding checklist** (`routes.ts` + frontend)  
`GET /api/users/me/onboarding` returns `{steps: [{id, label, done}]}`:
- `first_workflow_run` — has the user run any workflow to terminal state?
- `profile_complete` — domain preference set?
- `file_uploaded` — has the user uploaded a file?
Shown as a mini checklist in the sidebar for the first 3 sessions.

**6C-4 — Empty-state copy** (`chat-interface.tsx`)  
Replace the blank chat interface with a welcome card that includes:
- BioMate's 3-line value proposition
- Domain-specific starter queries (from `GET /api/onboarding/suggestions?domain=genomics`)
- Link to user manual PDF

### Files
- `frontend/client/src/components/chat-interface.tsx`
- `frontend/client/src/components/feedback/post-run-micro-survey.tsx`
- `frontend/client/src/components/onboarding-checklist.tsx` (new)
- `frontend/server/routes.ts`

### DoD
- New user can go from registration → first workflow card in <3 clicks
- Survey only fires after terminal state, with "Not now" suppression
- E2E: `outsider-readiness.e2e.ts` extended with onboarding flow assertions

---

## Track 6D — Billing & Quota Enforcement (Low Priority / Parallel)

### Problem
Lago billing infrastructure is in place (Lambda + EC2) but:
- `billing null in dev` config gap noted in memory
- No enforcement: users who exceed pilot quota continue to run workflows
- No in-app usage indicator for the user

### What to build

**6D-1 — Quota check on workflow launch** (`routes.ts`)  
Before firing `POST /api/workflows/launch`, call Lago to check the user's
remaining vCPU-hours for the current billing period. If over quota, return
`402 { error: 'quota_exceeded', used: X, limit: Y }` and show a banner in the viewer.

**6D-2 — Usage indicator** (`nextflow-workflow-viewer.tsx`)  
Small "N vCPU-hrs used / M vCPU-hrs" meter in the viewer header, updated after
each run completes.

**6D-3 — Dev billing config fix**  
`LAGO_API_KEY` env var must be set in dev; add to `.env.example` with a placeholder.
Pilot account bypass (`PILOT_ACCOUNT_EMAILS`) already in place — quota check skips them.

### Files
- `frontend/server/routes.ts`
- `frontend/client/src/components/nextflow-workflow-viewer.tsx`
- `.env.example`

### DoD
- Non-pilot account over quota gets 402 and in-app banner
- Pilot accounts bypass quota check
- E2E: quota exceeded → banner visible

---

## Priority Order

| Track | Priority | Effort | Parallelisable |
|-------|----------|--------|----------------|
| 6A: S3 output delivery | P0 | 3–4 hrs | Yes |
| 6C: Pilot onboarding | P1 | 2–3 hrs | Yes |
| 6B: Memory P2 | P2 | 4–5 hrs | Yes |
| 6D: Billing quota | P3 | 2 hrs | Yes |

**Recommended start order**: 6A + 6C in parallel (both unblock pilot launch),
then 6B, then 6D.

---

## E2E Coverage Plan

| Test file | New tests |
|-----------|-----------|
| `e2e/session6-production.e2e.ts` | 6A: S3 output visible; 6C: onboarding flow; 6B: cross-session memory |
| `e2e/outsider-readiness.e2e.ts` | Extend with onboarding starter prompts |
| `e2e/pilot-study-e2e.e2e.ts` | Extend with quota enforcement case |

Target: 10–12 new E2E tests, all passing before declaring pilot-ready.

---

## Definition of Done

- [ ] Track 6A: AWS Batch outputs visible in viewer + FindingsCard for Batch runs
- [ ] Track 6B: Returning user sees past session context injected in new conversation
- [ ] Track 6C: New user reaches first workflow card in ≤3 clicks; survey fires post-terminal
- [ ] Track 6D: Over-quota non-pilot accounts blocked at launch; usage meter visible
- [ ] E2E: 10+ new green tests in `session6-production.e2e.ts`
- [ ] Branch merged to `stronger_backend` with clean CI
