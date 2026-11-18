# Pre-Sync Checklist

**Rule:** Run every step below before `scripts/sync_to_dev.sh`. Stop and fix on first failure.

The 2026-06-03 Galaxy crash-loop (PEP 604 union syntax in a function signature evaluated by gunicorn's worker startup) would have been caught at step 3 in <1 second. Tests-after-sync is debugging in production; tests-before-sync is debugging on your laptop.

---

## **HARD RULE: when a build/deploy fails, read the full error BEFORE retrying.**

Wasted-cycle incidents in this repo trace to a single anti-pattern: a
truncated error string ("exit code 1", "Failure", "HTTP 500", "No
content") gets interpreted via guess-and-retry instead of by reading
the full log. The answer is **almost never in the retry** — it's in
the part of the output that was cut off.

**Documented examples this discipline would have prevented:**

| Date | Incident | Cost |
|---|---|---|
| 2026-06-07 | biotools `pip install exit 1` → assumed disk full → cleanup retry → disk extension → still failed. 30-second isolated `pip install numpy` showed `error: externally-managed-environment` (PEP 668). Fix: one Dockerfile flag. | 3 wasted rebuild cycles (~30 min each) |
| 2026-06-07 | Gemini "No content in Gemini response" → assumed model version → tried `gemini-3.5-flash` → still empty. Capturing raw API response showed `thoughtsTokenCount: 1798` ate the entire `maxOutputTokens=1000` budget. Fix: `thinkingBudget: -1` + bump default tokens. | 2 wasted sync cycles |
| 2026-06-07 | `sync_to_dev.sh` "Sync OK" but new code never on dev. The scp had returned non-zero but the tar extract step swallowed it via `\|\| true` and re-applied stale leftovers. Logs showed `scp: failed to upload`. | 1 phantom-deploy debug session |
| 2026-06-03 | Galaxy 502 crash-loop. Truncated log said `[FATAL] Unhandled rejection: error` → first guess was network. Full traceback showed `relation "download_jobs" does not exist` — the migration wasn't applied. | 30 min of network-side debugging before checking the table |

**How to apply on the next failure:**

1. **Find the truncated bit.** If the log was capped (e.g. `tail -5`,
   `... | head -10`, sync wrapper buffering), get the full version
   first: `cat /tmp/biomate_frontend_build.log`, `docker logs $C`,
   `aws ec2 describe-volume-modifications`, etc.
2. **Reproduce the failing step in isolation** if the full log doesn't
   immediately disambiguate. A `docker run --rm base bash -c '<the
   failing command>'` is usually 30 seconds. A `curl` against the API
   that's 500'ing usually returns the actual exception in the body.
3. **Only then change anything.** No guess-fixes, no "let me bump
   memory and see", no "let me retry — maybe it was transient" unless
   you can NAME the transient (e.g. "rate-limited at request N, retry
   after backoff").
4. **Never reuse an exit code as a diagnosis.** "Exit 1" means "the
   author of this binary refused to return 0" — it's not a category.

---

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
When the change touches the critic layer (the post-run hook attaches via
`from galaxy.ai.critics import …` inside `nextflow_executor.py`), ALSO import the
critics package directly — the attach's `try/except` protects runtime, not import
time, so a bad import in `galaxy.ai.critics` would crash Galaxy at module load:
```bash
cd backend && PYTHONPATH=lib python3.9 -c "import galaxy.ai.critics"
```
**Catches:** module-load failures — most importantly PEP 604 `X | Y` annotations on Python 3.9 (Galaxy container is 3.9), missing imports, syntax errors. ~3 s.

This is the step that catches PEP 604 / missing-import bugs **before** they take dev down. The future-import gotcha exists because:
- `from __future__ import annotations` defers most annotations
- But gunicorn's worker class can eagerly evaluate them via FastAPI route registration paths
- A direct `python3.9 -c "import …"` reproduces the same eager-eval behaviour

### 3b. Workflow chain lint (any change to chains, workflows, or `galaxy_ai_tools.db`)
```bash
python3 scripts/lint_workflow_chains.py   # exit 0 = required chains clean; exit 1 = fix before sync
```
**Checks:** for each required-clean chain, every step resolves to an executable workflow and every connection's `to_input` is a parameter the downstream workflow declares (`params.X` in `main.nf` or `nextflow_schema.json`). Undeterminable connections are listed as WARN only. Other chains get a one-line count (`--all` for details).
**Why:** the executor injects the upstream artifact as `params[to_input]`; an undeclared name launches a doomed Batch job at step 2 or 3. See `docs/20261101_WORKFLOW_CHAIN_AUDIT.md`. Offline unit test: `python3 -m unittest scripts.test_lint_workflow_chains`.

### 4. Domain-specific integration test
If your change touches a documented surface, run its integration test:

| Surface modified | Test |
|---|---|
| `frontend/client/src/v2/AfterRunReport.tsx` or related backend endpoints | `python3 scripts/test_afterrun_comprehensive.py` |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/` (workflow .nf files) | `python3 scripts/test_phase_groups.py` (TODO: move from `/tmp/`) |
| New backend FastAPI route | `curl -sf http://localhost:8081/<your-route>` (after starting local Galaxy backend) |
| Workflow execution flow | Existing Playwright e2e in `frontend/e2e/` |

### 4b. Workflow integrity guard — fabrication class gate (HARD)
Run whenever you add/modify a workflow `.nf`, or change any `executable` flag, or sync the DB:
```bash
python3 scripts/audit_fabrication.py   # exit 0 = clean; exit 1 = an executable workflow fabricates
```
Enforces the invariant **no `executable=1` workflow fabricates its outputs** (RNG → written output,
no input read — code lines only). This is the class guard for the MERFISH / "Analyze-Quantify"
fabrication stubs (`docs/20261002_FABRICATION_AUDIT.md`). A FAIL is a triage gate, not auto-block:
rewire the workflow to a real tool, OR set `executable=0`, OR — if the RNG is legitimately the
workflow's purpose (array/IO package, simulation, honestly-labeled synthetic demo) — add its id to
`ALLOWLIST` in the script **with a reason**. Needs the full enriched `galaxy_ai_tools.db` (not the
local stub), so run it in CI or after an S3 DB pull. Do NOT sync a DB that trips this gate.

### 5. Sync to dev — only after 1–4 pass
```bash
git add <files> && git commit -m "<message>" && git push origin <branch>
bash scripts/sync_to_dev.sh
```

**Ops playbook (one-writer, DB matrix, proxy/SSM, no hot-patch):** see
`docs/20261113_COMMIT_PR_SYNC_PROCESS.md`. Use `BIOMATE_SYNC_DB=0` when shipping
code without the local catalog; do not sync DEV from two worktrees at once.

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
