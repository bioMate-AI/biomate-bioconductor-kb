# Systemic fix — bioconductor `take:`-subworkflow launch (no-input + flakiness)

**Date:** 2026-09-21
**Trigger:** the hospital-instrument E2E suite caught qPCR (`normqpcr_delta_delta_cq_normalization`) failing at execution. SSM ground-truth showed it fails at **Nextflow launch (422)**, not in the R. Root-causing revealed a systemic issue in the bioc entry-wrapper path.
**Method note:** follows the `systemic-root-cause` playbook — one upstream source, ground truth from the real runtime, close the whole class with a guard + test.

## Blast radius (why this matters)
**3,360 of 3,364** bioconductor subworkflow `.nf` files (`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/**`) have a **`take:` block and NO anonymous `workflow { }`**. They are all launch-gated by one function: `_build_bioc_entry_wrapper` (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:1746`). If it returns `None`, the caller (`:5492` → guard `:5503`) raises a 422 and the run dies before any R executes. So this single wrapper path gates ~the entire bioconductor catalog.

## Two failure modes (both observed on dev)

### A. No-input "try sample data" / demo → 422 (deterministic)
Style-A workflows declare their inputs via a `// Input: <names>` header (qPCR: `// Input: example.txt`). The wrapper requires each declared name to be present as a param to stage it (`:1801-1816`). For a **no-file run** (one-click demo, or an inline-data chat that binds no file — `inputBindings: []`), no such param exists → the multi-omics fallback collects nothing → wrapper returns `None` → `:5503` raises 422:
> `…declares input channels (a take: block) that -entry alone cannot bind, and no entry wrapper could be generated…`
The R's own no-input demo fallback (the package example) **never runs** because launch fails first. **This blocks the entire "try the platform with sample data" experience for the bioconductor class.**

### B. With-file launch is FLAKY (~3 of 4 dispatches fail)
With a real uploaded Ct file, the wrapper's file-param fallback (`:1816-1835`) collects the file and the workflow **can** run to COMPLETED — **proven**: qPCR upload dispatch reached `completed` (RID `ea45b0de-b7c4-40b6-8667-50dff0c434ce`). But 3 of ~4 recent `normqpcr` dispatches failed first (E2E verdict: *flaky, fail→pass on retry*). Root cause of the intermittency is **not yet isolated** — candidates: non-deterministic file-param collection in the multi-omics fallback (which params are file-valued can vary by run), an S3-staging race, or intermittent Batch/container-pull. **Needs a dedicated repro-and-log pass before fixing.**

## Evidence
- SSM (`docker logs biomate-galaxy-dev`): repeated `workflow.failed … launch failed (422): … no entry wrapper could be generated` for no-file runs (inv `58b13f92`, `867ad5ab`).
- Run API: `execution.status=failed`, `error=null`, `inputBindings=[]` (no-file case) — the record carries no error; the panel binds errors via SSE/log endpoints.
- One clean `completed` normqpcr run with an uploaded Ct file → generalization validated.
- E2E: `frontend/e2e/hospital-instruments-upload.e2e.ts` (qPCR dispatch arm) → flaky.

## Design

### Fix A — make no-input runs launchable (unblocks demo/try-it)
When a Style-A workflow's declared inputs are absent, the wrapper should **not** return `None`. Instead build a wrapper that binds a **valid empty/placeholder channel** so the workflow launches, and let the `.nf`'s own no-input demo fallback (already present in qPCR and the B8/HTS parsers) provide the sample data. Concretely, in `_build_bioc_entry_wrapper`:
- If `names` is non-empty but **no** declared/file params resolved AND the process input is a single list slot (`path(input_files, stageAs:'?/*')`, `n_path<=1`), emit a wrapper that binds `Channel.of([meta, []])` (empty file list) rather than returning `None`.
- Guard: a `path(input_files, stageAs:'?/*')` slot tolerates an empty list (many files → one list; zero files → empty). Verify Nextflow accepts an empty-list `path` here; if not, bind a **non-data placeholder** whose extension is outside the `.nf`'s own input-detection set so the R demo path (not the generic path) is taken.
- This aligns the launch layer with the sample-data mechanism in `docs/20260921_WORKFLOW_SAMPLE_DATA_COVERAGE.md`.

### Fix B — de-flake the with-file launch
1. **Repro + log first** (do NOT guess): dispatch `normqpcr` with the same uploaded Ct CSV N=10 times; capture per-run the `bioc entry wrapper: … staged=%d` line (`:1994`) + the 422 vs success. Diff a failed vs passed run's wrapper inputs.
2. **Most likely fix:** make the multi-omics file-param collection **deterministic** (stable ordering; explicit "which param is the input file" resolution instead of scanning all file-valued params). Only after determinism is restored consider a bounded launch retry — never a retry that masks a real bind failure.
3. **Acceptance:** the qPCR upload-dispatch E2E must pass **K consecutive times** (e.g. 5/5), not "flaky, passes on retry."

### Verification (the acceptance gate)
- Extend the hospital-instrument E2E with a **no-input demo dispatch** for qPCR (proves Fix A) alongside the existing upload dispatch (proves Fix B).
- Both must reach `completed` **K/K** runs.
- Add a **wrapper unit test** (pure-Python, no Batch) over `_build_bioc_entry_wrapper` covering: Style-A with input, Style-A no-input (new empty-channel path), Style-B placeholder — so this class can't silently regress.

## Rollout
Executor-only change (`nextflow_executor.py`) → commit → PR to `next-phase` → merge → `sync_to_dev.sh` → run the E2E acceptance gate K times on dev. Conservative + unit-tested because the blast radius is ~3,360 workflows.

## Explicitly out of scope here
- The R-level qPCR generalization + demo fallback are **already shipped and validated** (real Ct → COMPLETED). This doc is only the **launch/wrapper** layer.
- Flow-cytometry `.fcs` fixture (separate item) so its dispatch becomes testable.

## UPDATE 2026-09-22 — Fix A shipped & validated; remaining issue re-scoped

**Fix A (no-input launch) is IMPLEMENTED, synced, and validated.** `_build_bioc_entry_wrapper` now binds a `.dat` placeholder for the single-list-slot no-input case instead of returning None. Live evidence on dev: pre-Fix-A no-input runs `abd5958f`/`9f197935` **failed at launch (422)**; post-Fix-A run `7c9dfd0a` **reaches `running`** (no 422). The launch 422 is resolved for the class.

**UPDATE 2026-09-22b — the "hang" was NOT a dep-install hang; SSM ground truth found TWO concrete issues:**

The Fix A validation run's Batch job (`c2d93566`) **FAILED in 13 s** (not hung). Its `.command.log` (S3 work-dir): Fix A + the demo fallback both ran (`[biomate demo] … using the NormqPCR bundled example`), then halted at:
`Error in -0.01 * height : non-numeric argument to binary operator; Calls: barplot`.

- **Issue 1 (FIXED):** the demo-path barplot fed a **character/factor** `2^-ddCt` column (that's how `deltaDeltaCq()` returns it) into `barplot()`, halting the run. Fixed by coercing to numeric (`fix(qpcr): demo-path barplot…`). The generic path was already numeric (`log2FC`) — which is why the uploaded-file run completed. So the no-input demo now runs to completion (dep-install was fine; the container's packages loaded normally — Bioconductor/qpcR/etc. all loaded in the log).
- **Issue 2 (OPEN — orphan finalization):** the Batch job FAILED at 14:48 yet the run still shows `running` (and `fefa4723` shows `running` ~13 h). The executor keys completion off the local `nextflow` process exit + **S3 output files**, not Batch **job status** — so when a job FAILS without writing outputs (and/or the local process/worker dies), the run is never reconciled and sits `running` forever. **Code entry points** (`nextflow_executor.py`): finalization at `:4268-4301` (`final_status`/returncode) and `:6696`; `_scrape_batch_job_ids(run_id)` at `:4362`; the background completion `_poll()` at `:3502`; plus the `CompletionPoller` + `orphan_finalizer.finalize_orphaned_run` described in CLAUDE.md (Run-State-Persistence section). **Fix:** in the poller, `aws batch describe-jobs` the scraped job ids; on terminal `FAILED` (with no outputs) finalize the run `failed`; add a wall-clock budget so a run can't sit `running` indefinitely. This is the real reliability work — NOT dep-install.

So the launch layer (Fix A) + the demo R bug (Issue 1) are done; the remaining systemic piece is **Batch-job-status reconciliation (Issue 2)**, not container dep-install. (Original speculation about `BiocManager::install` hanging was WRONG — the log shows packages loaded fine.)


- Dev chat-stream outage: fixed + live.
- Hospital-instrument E2E (routing/UX/upload/folder): green.
- qPCR generalization: validated end-to-end (flaky launch is THIS doc's subject).
