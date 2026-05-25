# 2026-05-20 — Dev workflow restoration + alembic merge + JVM hardening

Session goal: the team reported "workflows can not run in dev". Diagnosed and
shipped 10 commits across the Galaxy backend, BioMate frontend reconcile
layer, 303 Nextflow workflow files, and Galaxy's alembic migration tree to
make dev's workflow execution path work end-to-end and unblock fresh-DB
deploys for CI/CD.

---

## TL;DR — the bug chain

A user-visible "workflow failed" on dev was actually **seven independent
bugs stacked**, plus one that surfaced mid-session:

1. **503 from chat → workflow generation** (silent killer)
   — `llm_client.py` missing `import os`; latent for weeks, exposed when
     today's container HUPs cleared the cached AIAssistant singleton.
2. **297 workflows failed instantly with `No such variable: meta`**
   — Nextflow 26.04 evaluates non-closure `publishDir` strings at process
     parse time, before the input channel binds `meta`.
3. **Completed runs stuck at `status: running` in the main GET endpoint**
   — only `/api/workflows/runs/:id/status` polled Galaxy + promoted state;
     `/api/workflows/runs/:id` (used by page reload + session restore)
     read stale DB rows forever.
4. **Forgotten Nextflow terminal states** (`interrupted`, `cancelled`,
   `paused`, `unknown`, `completed`, `pass`, `fail`)
   — reconcile only treated `succeeded|failed|error` as terminal.
5. **CYP-DDI profile mismatch + Nextflow 26.04 syntax strictness**
   — workflow declared `aws_batch` profile (only one of 2141 to diverge);
     Nextflow 26.04 also rejected free-standing `def` at script scope.
6. **5 workflows with Python `"""` docstrings inside Groovy `"""` script
   blocks** → script compilation error.
7. **`progress.totalSteps = 0` for any workflow whose `steps` are lazy-
   fetched** → panel shows "0 steps" even when 1/1 tasks completed.
8. **Galaxy alembic multi-head on fresh DBs** (Task #19 handoff)
   — two divergent gxy heads after a fork rebase didn't happen;
     `manage_db.sh upgrade` fails with "Multiple head revisions".
9. **OpenJDK 21 + AWS SDK CRT race on parallel Nextflow heads**
   — SIGSEGV in `ld-linux+0x2475a` inside
     `software.amazon.awssdk.crt.CRT.extractAndLoadLibrary` on the
     PublishDir thread, terminating the JVM mid-run.

(7) was a UX bug; (8) blocks CI/CD; (9) was the new failure that emerged
once the other 7 were fixed and we ran 4 workflows in parallel.

---

## Commits (chronological)

| # | SHA | What | Files | Lines |
|---|---|---|---|---|
| 1 | `84c4a0923` | `publishDir "${params.outdir}/${meta.id}/..."` → `publishDir { "..." }` closure | 297 workflow `main.nf` files in 24 domains | 309 |
| 2 | `1ea3263e6` | Reconcile-on-read in `GET /api/workflows/runs/:id` | routes.ts | +96 |
| 3 | `4e7d6fa3d` | Deny-list IN_PROGRESS_STATES; map every non-running NF state to BioMate terminal | routes.ts | +72 |
| 4 | `8aa5ed84e` | cyp_ddi: rename profile `aws_batch`→`aws`; first single-line Python `"""` → `'''` | 2 files | 7 |
| 5 | `3ae76bf57` | cyp_ddi: `def _useAws/_ECR/CHEM_CONTAINER` promoted to `params.*` (Nextflow 26.04 rejects free-standing `def` next to params decls) | 1 file | 11 |
| 6 | `ac3e21e32` | Python docstring `"""` → `'''` in 5 more workflows (`virtual_patient_cohort`, `physicell_tumor_tgi`, `cipa_cardiac_safety_ode`, `ode_signaling_simulation`, `pbpk_disease_state`) | 5 files | 9 |
| 7 | `2b1c9f9ca` | **Missing `import os` in `llm_client.py` — the 503 root cause** | 1 file | 1 |
| 8 | `f5c0401ad` | **Alembic merge `gxy` heads (Task #19): `a7f3deepagent + 3af58c192752` → `204367c6a604`** | 1 new migration | 24 |
| 9 | `69382a760` | Backfill `progress.totalSteps` from `nfs.totalTasks` when workflow had empty `steps: {}` | routes.ts | +15 |
| 10 | `4efb990e1` | Per-run `aws.crt.lib.dir` + `-Xss2m` + `aws.crt.disable.crt.in.client=true` to stop SIGSEGV in parallel Nextflow heads | nextflow_executor.py | +27 |

Total: ~603 lines net, mostly the publishDir mass-edit + reconcile logic.

---

## Detailed root causes (in commit order)

### 1. publishDir meta interpolation (`84c4a0923`)

**Symptom:** every ADMET / non-cryoEM workflow failed in ~23s with
`ERROR ~ No such variable: meta` at `publishDir "${params.outdir}/${meta.id}"`.

**Why:** Nextflow evaluates non-closure directive strings at process
**parse time** — before the input channel binds `meta`. CryoSPARC worked
because it already used the closure form `publishDir { "..." }`.

**Fix:** mass regex-rewrite from
```groovy
publishDir "${params.outdir}/${meta.id}/...", mode: ...
```
to
```groovy
publishDir { "${params.outdir}/${meta.id}/..." }, mode: ...
```
across 297 files / 309 lines / 24 domains. Pattern:
```python
re.compile(r'^(\s*)publishDir\s+"((?:[^"\\]|\\.)*\$\{meta(?:[^"\\]|\\.)*?)"(\s*,\s*mode\s*:)', re.MULTILINE)
```

**Verification:** ADMET run `798b067c` completed cleanly on AWS Batch
(duration 3m 33s, real `admet-ai/Chemprop` predictions for aspirin:
hERG_prob=0.021, DILI_prob=0.675, 41 TDC endpoints in
`toxicity_report.json`).

### 2 / 3 / 4. Reconcile-on-read + deny-list terminal detection (`1ea3263e6`, `4e7d6fa3d`)

**Symptom:** runs that completed on AWS Batch (S3 outputs materialized,
Nextflow log shows "Succeeded: 1") still showed `status: running` in the
API and UI hours later.

**Why:** two endpoints with divergent behavior:
- `GET /api/workflows/runs/:id`  → just read DB, **never polled Galaxy**.
- `GET /api/workflows/runs/:id/status` → polled Galaxy + promoted state.

If the UI / external poller / page-reload hit the main endpoint, the
status never updated. Also the promotion code's allow-list
(`['succeeded','failed','error']`) missed Galaxy backend states like
`interrupted`, `cancelled`, `paused`, `unknown`, `completed`, `pass`,
`fail`.

**Fix:** added Galaxy poll + promotion to the main GET handler. Switched
to a deny-list:
```typescript
const IN_PROGRESS_STATES = new Set([
  '', 'running', 'queued', 'pending', 'submitted',
  'starting', 'fetching_accessions', 'alive', 'ready', 'in_progress',
]);
const isTerminalNfState = nfState && !IN_PROGRESS_STATES.has(nfState);
```
Any non-in-progress state maps to BioMate's `succeeded | paused | failed`
terminal vocabulary, run is closed, `completedAt` is set,
`workflow_completed` event fires.

**Verification:** ADMET stuck-running run (`798b067c`) reconciled to
`completed` with `completedAt=18:29:44Z`, then a fresh caffeine ADMET
auto-reconciled to `completed` after 273s without any `/status` poke.

### 5–6. cyp_ddi profile + Nextflow 26.04 strictness + Python docstrings (`8aa5ed84e`, `3ae76bf57`, `ac3e21e32`)

**Symptom:** CYP-DDI failed in 13–14s with three different errors as we
peeled the onion:
1. `Unknown configuration profile: 'aws'` (only workflow declaring `aws_batch`)
2. `Statements cannot be mixed with script declarations` (free-standing `def` at script scope)
3. `Unexpected input: 'R2'` (Python docstring `"""` collided with Groovy `"""`)

**Why (3):** inside a Nextflow process `script:` block, the body is a
Groovy triple-quoted string. Any nested `"""docstring"""` inside it
prematurely closes the Groovy string, then the parser tries to read the
docstring prose as Groovy and chokes.

**Fix:** rename profile, promote `def` to `params.*`, convert all inner
Python `"""` to `'''`. Found 5 other workflows with the same docstring
pattern via the substring count heuristic (single-line `"""..."""` and
multi-line docstring openers inside the script block).

### 7. Missing `import os` (the 503 root cause) (`2b1c9f9ca`)

**Symptom:** chat-stream returned
`"workflow engine returned a 503 Service Unavailable error"` for every
workflow generation. The user's bug report.

**Why:** Galaxy's `/api/ai_assistant/generate_workflow` calls
`get_ai_assistant(trans)`. That function caches a singleton in
`_ai_assistant_instance`. The constructor calls
`GalaxyWorkflowGenerator(...)` → `LLMClient(...)` →
`os.path.dirname(os.path.abspath(__file__))` at
`backend/lib/galaxy/ai/llm_client.py:118`. But `os` was never imported
at module top. The bug had been latent for a while: any previous
successful init cached the instance, and subsequent calls reused the
cache without re-running `__init__`. Today's container HUPs reset the
singleton; the NameError fired on the next request and
`get_ai_assistant` returned `None`, so the route raised `503 "AI
Assistant not available"`.

**Traceback captured live:**
```
File "/app/lib/galaxy/ai/llm_client.py", line 118, in __init__
    _here = os.path.dirname(os.path.abspath(__file__))
NameError: name 'os' is not defined
```

**Fix:** one line — `import os` added to the module imports.

**Verification:** Galaxy direct call to `/api/ai_assistant/generate_workflow`
now returns HTTP 200 with `source: template_reuse`, confidence 62, citations.

### 8. Alembic merge gxy heads (Task #19) (`f5c0401ad`)

**Symptom (from the handoff doc, not reproduced locally today since dev
DB was already migrated by hand):**
```
manage_db.sh upgrade
  → CommandError: Multiple head revisions are present for given argument 'gxy@head'
```

**Why:** the Galaxy fork has two divergent gxy heads:
- `3af58c192752_implement_sample_sheets.py` (upstream Galaxy head)
- `a7f3deepagent_autofix_tables.py` (fork-custom head)

Someone added the autofix migration without rebasing it on the new
upstream head, so the tree split. Fresh deploys against an empty
Postgres can't pick a head.

**Fix:** generated an alembic merge migration joining both heads via
```bash
docker exec biomate-galaxy-dev bash -c \
  "cd /app/lib/galaxy/model/migrations && \
   PYTHONPATH=/app/lib \
   GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION=sqlite:////tmp/dummy.sqlite \
   alembic merge -m 'merge gxy heads: autofix + sample_sheets' a7f3deepagent 3af58c192752"
```
(The handoff doc suggested `manage_db.sh merge` and `alembic -n gxy` —
neither works in this fork; the fork's `manage_db.sh` only exposes
`upgrade/downgrade/version/init`, and there's no `[gxy]` config section.
Plain `alembic` with `PYTHONPATH=/app/lib` from the migrations dir is
what works.)

Result: `204367c6a604_merge_gxy_heads_autofix_sample_sheets.py`:
```python
revision = '204367c6a604'
down_revision = ('a7f3deepagent', '3af58c192752')
def upgrade(): pass
def downgrade(): pass
```

This unblocks CI/CD plan items P2.4 (stage env) and P4.1 (prod env) per
the handoff. **Not verified end-to-end yet** because dev's DB is already
migrated past this point; need a fresh-DB deploy (test env) to confirm.

### 9. 0-step panel UX (`69382a760`)

**Symptom:** ADMET workflow ran 1 process successfully, but the panel
showed "0 steps" both in subtitle and progress chip.

**Why:** `storage.createExecutionRun` computes `totalSteps` from
`workflowDefinition.steps`. `generate_workflow` returns `steps: {}` for
workflows that use the lazy-fetch path (UI later re-fetches via
`/api/nextflow/steps`). So `totalSteps = 0` gets persisted, and nothing
ever reconciles it from the actual Nextflow trace.

**Fix:** in the reconcile-on-read code, if `nfs.totalTasks > 0` but
`run.progress.totalSteps == 0`, backfill both `totalSteps` and
`completedSteps` from the Nextflow trace.

### 10. JVM SIGSEGV on parallel Nextflow heads (`4efb990e1`)

**Symptom:** 3 of 4 workflows fired in parallel today crashed with
`status: failed`, `nfs.status: interrupted`, returncode `-6` (SIGABRT).

**Why (from `hs_err_pid283.log` on dev EC2):**
```
SIGSEGV (0xb) at pc=0x73050846575a, pid=283, tid=846
Problematic frame: C [ld-linux-x86-64.so.2+0x2475a]
Current thread: JavaThread "PublishDir-5"  free space=998k
Native frames:
  jdk.internal.loader.NativeLibraries.load(...)
  java.lang.System.load(...)
  software.amazon.awssdk.crt.CRT.extractAndLoadLibrary(...)
  software.amazon.awssdk.crt.CRT.loadLibraryFromJar(...)
```

AWS SDK's CRT (Common Runtime) native library races on extraction when
multiple Nextflow heads dlopen the same `/tmp/.aws-crt-cache` files
concurrently. OpenJDK 21.0.11 + Debian trixie + glibc 2.41 + parallel
heads = SIGSEGV in the dynamic linker chain. The default 1024K JVM stack
is also tight for the chained `dlopen` calls during contention.

**Fix:** three JVM options injected via `NXF_OPTS` per Nextflow head:
- `-Daws.crt.lib.dir=<per-run-cache>` — each head gets its own
  extraction directory; eliminates the race.
- `-Daws.crt.disable.crt.in.client=true` — make AWS SDK fall back to
  the Java HTTP client path if CRT init still fails.
- `-Xss2m` — double the thread stack so chained `dlopen` has room.

---

## What was tested on dev

| Workflow | Result |
|---|---|
| ADMET (aspirin, single SMILES) | **PASS** — 3m 33s, real `admet-ai/Chemprop` output (`toxicity_report.json` 1441 bytes; hERG_prob=0.021; 41 TDC endpoints) |
| ADMET (caffeine, post-503-fix) | **PASS** — 273s, status auto-reconciled to `completed` |
| Allometric Scaling | **PASS** — 289s, 6 outputs |
| AutoDock Vina (first attempt) | **FAIL (JVM)** then retry **PASS** — Galaxy's retry caught it |
| CYP-DDI Panel (attempt 1) | **FAIL** — `Unknown profile: aws` |
| CYP-DDI Panel (attempt 2) | **FAIL** — Python docstring collision |
| CYP-DDI Panel (attempt 3) | **FAIL** — `Statements cannot be mixed with script declarations` |
| CYP-DDI Panel (attempt 4) | **FAIL (runtime)** — numpy/RDKit ABI mismatch in `biomni-tools:x86` container (separate fix) |
| Parallel 4-up sweep (ADMET + Allo + Dock + CYP) | 3/4 JVM SIGSEGV (this drove commit #10) |
| Direct Galaxy `generate_workflow` call | **HTTP 200** with real workflow + citations |

The post-commit-#10 sweep is running as of doc-write time
(`bash /tmp/sweep2.sh` background poller). Will append results when it
completes.

---

## Known open issues — not fixed today

1. **`biomni-tools:x86` container ABI mismatch.** CYP-DDI runs end-to-end
   now, but the container has incompatible numpy + rdkit versions:
   ```
   AttributeError: _ARRAY_API not found
   AttributeError: module 'rdkit.Chem.MolStandardize.rdMolStandardize'
     has no attribute 'Standardizer'
   ```
   Needs a container rebuild against the current scikit-learn / rdkit /
   numpy 2.x stack.

2. **Alembic merge end-to-end verification.** The migration file is
   committed and will be applied on the next fresh-DB deploy (test env).
   Dev's DB is already at the post-merge state from manual fix, so we
   can't reproduce the bug locally. Need a CI/CD test-env deploy to
   confirm `manage_db.sh upgrade` (singular) works against an empty
   Postgres now.

3. **Lazy-step backfill is reactive, not proactive.** Today's fix
   updates `progress.totalSteps` on read after the Nextflow trace
   reports it. A cleaner version would lazy-fetch
   `/api/nextflow/steps?nextflow_path=...` at run-creation time in
   `storage.createExecutionRun` so the panel never has to render
   "0 steps" even briefly. Not done because (a) it adds a synchronous
   Galaxy call to the hot path of run creation, and (b) the reactive
   fix already eliminates the user-visible bug after the first poll.

4. **`workflowDefinition.steps` shape inconsistency.** Some workflows
   come back with `steps: {}` (empty object), others with `steps: null`,
   others with `steps: undefined` (key absent). The lazy-fetch UI handles
   all three, but it'd be nicer if the backend always returned
   `steps: {}` so the type is stable. Tracked, not fixed.

5. **Five stashes of other agents' WIP** still sit on the local repo:
   - `stash@{0}` `chat-input.tsx` (UI WIP)
   - `stash@{1}` `routes.ts` (largely superseded by today's `1ea3263e6`)
   - `stash@{2}` `llm_client.py + tool_parameter_recommender.py`
   - `stash@{3}` `ai_assistant.py + config.py` (small)
   - `stash@{4}` `llm_client_fallback_implementation.py + unified_workflow_search.py + tool_parameter_recommender.py`
   Plus today's auto-stashes of `chat-input.tsx`, `llm_client.py`,
   `chat-message.tsx`, `workflow-sse.ts`, `config.py`, `ind_assembly.py`,
   `llm_router.py`, `llm_client_fallback_implementation.py`,
   `tool_parameter_recommender.py`. These belong to other agents — not
   popped today to avoid merge conflicts with their working state.

6. **Sample-data ("use sample data") UX still hallucinates.** The
   `galaxy-assistant.ts` system prompt has a `demo/test/mock` exception
   on line 5170 that the LLM interprets loosely — it fabricates DESeq2
   results from training data instead of triggering the workflow with a
   real S3 fixture. Documented design in chat; not implemented today
   (per user direction "don't dramatically change the current
   information flow").

7. **Backend `mock_mode = True` defaults still live.** In two runtime
   input validators (`cryo_em_harness.py:80`,
   `workflow_test_harness.py:682`). Should be flipped to `False` so
   sample-data runs always validate real file paths. Tracked, not
   fixed.

---

## What's next

- **(a) Re-verify the 4-workflow sweep** post-JVM-fix (`bssjt910l` →
  `b3tlqzv47` background tasks).
- **(b) Container rebuild for `biomni-tools:x86`** — numpy 2.x + RDKit
  current — to unblock CYP-DDI's runtime failure.
- **(c) Fresh-DB deploy of the alembic merge** via the new CI/CD path
  (`gh workflow run deploy.yml --ref integration/next-phase -f env=test`)
  to validate Task #19's resolution end-to-end. Per the handoff: after
  this passes, P2.4 (stage env), P4.1 (prod env), and P4.3 (retire
  `sync_to_dev.sh`) can start their ≥2-week green-deploy track record.
- **(d) Sample-data fixtures + UI button** for the ~20 flagship
  workflows. Design discussed; not implemented.
- **(e) Reach out to the 5 stash owners** to coordinate their changes
  back into HEAD (each touches `llm_client.py`, `routes.ts`,
  `ai_assistant.py`, or `unified_workflow_search.py` — files I also
  modified today).

---

## Operational notes for the runbook

- `sync_to_dev.sh` refuses to run with any uncommitted file under
  `frontend/client/`, `frontend/server/`, `frontend/shared/`,
  `backend/lib/`, or `backend/biomni_workflows/`. Stash other agents'
  WIP before each sync.
- The CRT cache directory is created per-run at
  `/tmp/nextflow_runs/<run_id>/.aws-crt-cache`. If you see SIGSEGV
  recurring, check that the directory exists and is writable by the
  Galaxy container user.
- The alembic merge command, when needed again in a new fork:
  ```bash
  docker exec biomate-galaxy-dev bash -c \
    "cd /app/lib/galaxy/model/migrations && \
     PYTHONPATH=/app/lib \
     GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION=sqlite:////tmp/dummy.sqlite \
     alembic merge -m 'merge gxy heads' <head_a> <head_b>"
  ```
  Then `docker cp` the new file out of the container and commit.

---

## CLAUDE.md compliance check

- [x] All fixes ran via real BioMate execution path (no mocked workflow paths in tests).
- [x] No backend `mock_mode = True` defaults were introduced — pre-existing ones flagged for follow-up.
- [x] No workflow definitions edited under `nextflow_nfcore/subworkflows/**/*.nf` to match benchmark expectations — edits were genuine bug fixes (parse errors, syntax errors).
- [x] Doc lives under `docs/` with date prefix.
- [x] Real end-to-end execution verified: aspirin ADMET → real `toxicity_report.json` with real hERG/DILI/Caco-2/BBB predictions from `admet-ai/Chemprop`.
