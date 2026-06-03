# Pre-Sync Checklist

**Rule:** Run every step below before `scripts/sync_to_dev.sh`. Stop and fix on first failure.

The 2026-06-03 Galaxy crash-loop (PEP 604 union syntax in a function signature evaluated by gunicorn's worker startup) would have been caught at step 3 in <1 second. Tests-after-sync is debugging in production; tests-before-sync is debugging on your laptop.

---

## The five steps

### 1. TypeScript type check
```bash
cd frontend && npx tsc --noEmit -p .
```
**Catches:** wrong types, missing imports, prop-shape mismatches, dead `@ts-expect-error` directives. ~30 s.

### 2. Frontend unit + integration tests (vitest)
```bash
cd frontend && npx vitest run
```
**Catches:** regressions in any React component or Node route covered by `*.test.ts`. Includes the job-queue dedup + recovery specs, the workflow-execution SSE specs, etc. ~7 s.

### 3. Python import smoke for any modified backend module
```bash
cd backend && python3.9 -c "import galaxy.webapps.galaxy.api.<MODIFIED_MODULE>"
```
Replace `<MODIFIED_MODULE>` with whatever file under `backend/lib/galaxy/` you touched. For example, if you edited `nextflow_executor.py`:
```bash
cd backend && PYTHONPATH=lib python3.9 -c "import galaxy.webapps.galaxy.api.nextflow_executor"
```
**Catches:** module-load failures — most importantly PEP 604 `X | Y` annotations on Python 3.9 (Galaxy container is 3.9), missing imports, syntax errors. ~3 s.

This is the step that catches PEP 604 / missing-import bugs **before** they take dev down. The future-import gotcha exists because:
- `from __future__ import annotations` defers most annotations
- But gunicorn's worker class can eagerly evaluate them via FastAPI route registration paths
- A direct `python3.9 -c "import …"` reproduces the same eager-eval behaviour

### 4. Domain-specific integration test
If your change touches a documented surface, run its integration test:

| Surface modified | Test |
|---|---|
| `frontend/client/src/v2/AfterRunReport.tsx` or related backend endpoints | `python3 scripts/test_afterrun_comprehensive.py` |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/` (workflow .nf files) | `python3 scripts/test_phase_groups.py` (TODO: move from `/tmp/`) |
| New backend FastAPI route | `curl -sf http://localhost:8081/<your-route>` (after starting local Galaxy backend) |
| Workflow execution flow | Existing Playwright e2e in `frontend/e2e/` |

### 5. Sync to dev — only after 1–4 pass
```bash
git add <files> && git commit -m "<message>" && git push origin <branch>
bash scripts/sync_to_dev.sh
```
**Then post-sync smoke** against dev to confirm the deployed bundle/backend behaves as it did locally:
- For frontend: `curl -sf https://dev-public.biomate.ai/assets/index-*.js | wc -c` (size sanity)
- For backend: `curl -sf https://dev-public.biomate.ai/api/version` (200 = workers up)
- For new endpoint: hit it directly with `curl`

---

## When you can skip a step

- **Step 2** (vitest) can be skipped only if your change is a pure docs/markdown commit. Any `.ts/.tsx/.js` change → run it.
- **Step 3** (Python import) is mandatory for any `backend/lib/galaxy/**/*.py` edit. Skipping this is what produced the 2026-06-03 crash.
- **Step 4** is optional for trivial cosmetic changes (renaming, dead-code removal), required for any feature work.
- Never skip steps 1, 3, or 5.

---

## Background-task discipline

When a tool produces output asynchronously (long sync, agent dispatch), wait for the notification and read the output file before claiming "shipped" — don't assume success just because `git push` returned 0. The sync log frequently contains blocker errors that the wrapper exits with code 0 on.

---

## Why we don't have auto-commit-before-sync anymore

`sync_to_dev.sh` used to auto-commit dirty files before syncing. That was removed because it bypassed code review and produced commits like "chore: auto-sync" with no thought behind them. The current "Commit or stash them, then re-run" error message is intentional friction — it forces a real commit message.

When other sessions add dirty files to your tree mid-sync, you have two valid responses:
1. **Wait** for them to commit
2. **Commit them with a clear `chore: parallel-session edits (<context>)` message** — but only after looking at the diff to confirm nothing destructive

What you must NOT do: bypass the checklist because "the sync is in a hurry." The bypass is what produces dev outages.
