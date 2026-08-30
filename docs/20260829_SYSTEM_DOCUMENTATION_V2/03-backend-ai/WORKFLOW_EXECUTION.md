# 03b · Workflow Execution Engine

**Verified 2026-08-29** on branch `fix/resolver-prefer-real-nfcore-pipeline`. Source: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (**10,157 lines**) and `backend/lib/galaxy/ai/runs/`.

---

## 1. Nextflow executor

A FastAPI `Router` (L50) that launches **Nextflow head processes as detached local subprocesses** — it does *not* use Galaxy's invocation infrastructure. Only the workflow **tasks** run on AWS Batch.

**Routes:** `POST /api/nextflow/execute` (L5037), `GET /api/nextflow/steps` (L6226), `resume`/`cancel`/`pause` (L6256/6457/6469), `GET /status/{run_id}` (L6483), `outputs/download` (L7002), `runs/{id}/output_files` (L7057), `qc/profiles` (L7117), `qc-events` (L7146), `autoloop-suggestions` (L7273), `autoloop-dismiss` (L7303).

**Launch path:**
1. `execute_nextflow` (L5038) validates the path, mints `run_id`+`invocation_id`, precomputes the S3 outdir/workdir, writes a `configuring` record to **both** the in-process `_runs[]` dict and the run-state store, spawns a background `_launch_bg` thread, and **returns immediately** (async-return dodges undici's header timeout — incident 2026-06-30).
2. `_execute_nextflow_impl` (L5179) pops `profile`/`executor`, routes to AWS Batch when `NEXTFLOW_USE_AWS=true` or `executor=="awsbatch"`.
3. `_launch_nextflow_head` (L4868) is the single launch primitive: acquires a bounded-concurrency semaphore (default 10, `BIOMATE_NF_MAX_CONCURRENT` L139; 300s timeout → 503), then `subprocess.Popen(stdout=logfile, buffering=0, start_new_session=True)`. **FD-decouple is load-bearing** — `PIPE` blocks the JVM on gunicorn recycle. A reaper thread releases the semaphore slot on exit.

**AWS Batch targeting** — `_generate_executor_config` (L2567) writes a temp `biomate_executor_override.config` (Nextflow reads executor from config, not env). CPU queue `AWS_BATCH_QUEUE` default `biomate-nextflow-queue`; task container default ECR `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest` (L2626). Pins `nf-amazon` per workload (3.4.4 nf-core / 3.3.0 BioMate to dodge a JVM SIGSEGV) and substitutes `nf-schema` 2.4.2→2.5.1.

**Track & finalize** — `_stream_logs` (L4099) `process.wait()`s, then applies salvage logic: exit-0-but-empty → failed (`_looks_like_false_success`, def at L1216, invoked at L4145 within `_stream_logs`); exit-nonzero-but-S3-outputs-published → succeeded (`_looks_like_false_failure`, def at L1242, invoked at L4163); negative RC (signal) → `interrupted`. Writes terminal state to `_runs[]` + store, narrates a chat line, runs `_evaluate_qc_from_s3` (L3179).

**Concurrency invariant:** `_runs_lock` is a **reentrant `RLock`** (L70) — locked sections call lock-taking helpers; a plain `Lock` self-deadlocks. Request model `NextflowExecuteRequest` (L1354) carries `qc_overrides`, `qc_profile`, `compute_config`, `output_location`, `chain_meta`, `is_pilot`, `resume_from_run_id`.

## 2. Run-state persistence (`_runs[]` → Redis)

`backend/lib/galaxy/ai/runs/` — solves the gunicorn-recycle problem where `_runs[]` was wiped mid-run. Design: `docs/20260615_RUNS_PERSISTENCE_DESIGN.md`.

- **`run_state_store.py`** — `RunStateStore` **Protocol** (`set_run`/`update_run` [no-op if absent]/`get_run`/`delete_run`/`list_active_runs`/`set_pid`/`get_pid`/`acquire_completion_lock`). `InMemoryRunStateStore` (default). `RedisRunStateStore` — keys `nextflow:run:{id}` (hash), `:runs:active` (set), `:{id}:pid`, `:{id}:completing` (SETNX+EX lock), 7-day TTL. Factory `get_run_state_store()` reads `RUN_STATE_STORE` (default `memory`); the redis path pings and **falls back to InMemory on any failure** (so the L3 fix is silently inactive unless `RUN_STATE_STORE=redis`).
- **`completion_poller.py`** — `CompletionPoller(interval_s=5, min_run_age_s=5)` daemon thread `run-completion-poller`. `_sweep` → `list_active_runs` → `_maybe_complete`: checks `_pid_exists` (psutil / `os.kill(pid,0)`); if the process is gone, acquires the completion lock (120s TTL) and invokes the handler. **Detects orphaned subprocesses from ANY worker.**
- **`orphan_finalizer.py`** — `finalize_orphaned_run(store, run_id, record)`. `_read_returncode_from_disk` infers RC by precedence: launcher-log markers → trace task states → log-tail "Pipeline completed successfully"/"N of N ✔" → `s3_output_files` present → non-empty outdir → fallback (−1, interrupted). Updates the store (`finalized_by="orphan_poller"`), narrates chat, **POSTs `{FRONTEND_URL}/internal/runs/by-invocation/{invId}/status`** to flip the Postgres `execution_runs` row, writes a StudyRunLogger record, and runs S3 QC.
- **`bootstrap.py`** — `ensure_poller_started()` idempotent per-worker, called at module load (nextflow_executor.py L77–81) so every worker scans for orphans. Dev sets `RUN_STATE_STORE=redis` + `REDIS_URL=rediss://…`.

## 3. QC gates & auto-loop

Two gate systems feed a common SSE shape (`action` ∈ pass/advisory/halt, `level` ∈ GOLD/SILVER/BRONZE/FAIL).

- **Threshold DB — `qc_thresholds.json`** (root, 994 lines): `governance_layers` (RED_LINE/GOLD/SILVER/BRONZE/ADVISORY), `red_lines` (hard floors), per-domain `thresholds` (rnaseq, scrna_seq, atac_seq, chip_seq, wgs, wes, cryo_em, metagenomics, drug_discovery, crispr_screen), `named_profiles`. **hERG** (drug_discovery, `qc_thresholds.json:561`): `herg_ic50_high_risk_uM` 1.0 (GOLD blocking, FDA E14), medium 10.0 (SILVER), `herg_inhibition_prob_threshold` 0.9 (GOLD).
- **Cryo-EM gates — `cryosparc_qc_gates.py`** (776 lines): `QCResult` dataclass, `PROFILES` (default `cryoem_spa_purified`), `_ADVISORY_FACTOR = 1.30`. Gates: motion, ctf, junk-class, orientation, fsc, ab-initio, model-quality. Audit → `qc_audit.jsonl`. Fire inline in the CryoSPARC executor.
- **ADMET auto-loop (reactive/advisory — no auto-restart)** — `backend/experiments/autoloop_bridge.py` (492 lines): `classify_domain` → admet/docking/cyp_ddi/nca_pk/pbpk; the eval loop emits `autoloop_gate_results` SSE, splits REGULATORY vs RISK_STRATIFICATION halts, computes remediations, emits `autoloop_update` with `remediations`+`suggested_params`+`params_used`, and persists suggestions by `invocation_id` for `/autoloop-suggestions`. Evaluator `admet_autoloop/qc_evaluator.py` (`ADVISORY_BAND=1.15`; hERG HALT if IC50 < 10 µM). **Remediation "was→now"** — `param_tuner.py`: gap-proportional `step = HERG_BASE_STEP × log10(target/observed)` → `new_logp_max = current − step` (e.g. 5.0→4.71); analytical QSAR inversion when descriptors available; categorical DILI fix to Lammert-2010 (logp_max=4.0, mw=400); Ames `ames_strict=True`. Each `Remediation` carries `param_changes`, `rationale` (was→now + citations), `confidence`.

## 4. Autofix

`autofix3.py` (731 lines) + `backend/lib/galaxy/ai/workflow_ops/autofix/`. Diagnoses failed runs via multi-round LLM + native tool use, with iterative retry, duplicate-failure detection, risk gating, cost control, audit, and rollback.

- **API:** `POST /autofix3/run` (Path A: local run_id → `IterativeDebugger`; Path B: Galaxy invocation → `AutoFix3Orchestrator`), `sessions`, `realtime/status`, `error-summary` (Gemini Flash), `deep_diagnose` (Claude Sonnet). Sessions persist to `/tmp/biomate_autofix3_sessions/`.
- **Engine:** `iterative_debugger.py` (609) `run_until_fixed` (≤5 attempts), `_compute_error_hash` aborts after 2 duplicate failures; termination reasons SUCCESS / MAX_ATTEMPTS / DUPLICATE_FAILURES / NO_PROGRESS / MANUAL_ABORT / TIMEOUT. `agent.py` (908) `DeepAnalysisAgent.analyze` (Round-1 triage, Rounds 2–N tool investigation, synthesis). `base.py` — `RiskLevel`/`FixStatus`/`FixContext` (`ai_auto_fix_mode` safe/moderate/aggressive/manual).
- **Toolkit:** `toolkit_v2.py` (761) 7 sandboxed tools (Read/Edit/Bash/Glob/Grep/Write, blacklists `.env`/`.aws`/`.ssh`). `error_log_parser.py` (329, regex for cpu/OOM/file-not-found/gtf/star-index/container-pull/permission). Risk-gated: LOW auto-applies, MEDIUM confirms, HIGH manual. Phase-1 shipped `NextflowParameterFixer` (rnaseq/clipseq/smrnaseq/chipseq/atacseq).

### 4.1 The wider `workflow_ops/` diagnostic fleet

`autofix/` is one part of `backend/lib/galaxy/ai/workflow_ops/` (~28 modules) — the full failure-diagnosis / self-healing surface. Beyond autofix:
- **Diagnostic agents** (`workflow_ops/agents/`, all extend `BaseAgent`, built by `agent_factory.py`): `LogAnalysisAgent`, `RootCauseAnalysisAgent`, `ResourceOptimizationAgent`, `ParameterConfigAgent`, `NetworkDiagnosticAgent`.
- **Support modules:** `auto_healer.py`, `comprehensive_log_analyzer.py` / `log_analyzer.py` / `log_filter.py`, `aws_logs_fetcher.py`, `error_search_agent.py`, `fix_applier.py`, `parameter_analyzer.py` / `parameter_validator.py`, `nextflow_config_updater.py` / `nextflow_schema_loader.py`, `query_agent.py`, `samplesheet_generator.py`, `dataset_resolver.py`, `workflow_restarter.py`, `workflow_chat_narrator.py`, `notification_service.py`, `analysis_persistence.py`.

This is a distinct product surface (log/RCA/resource/parameter/network diagnosis) from the autofix loop. It is currently **untested-and-unlisted** — see the new [TEST_PLAN §3.6](../09-testing/TEST_PLAN.md).

## 5. CryoSPARC executor (a separate path)

`cryosparc_executor.py` (2,510 lines) — **not Nextflow, not Batch**. `execute_spa_pipeline` (L1313) returns a run_id immediately and runs a daemon thread. Compute is **EC2 + the CryoSPARC API directly**: `start_instance` (L359) launches a `g6.12xlarge` (4-GPU, `CRYOSPARC_INSTANCE_TYPE`) with a CloudWatch idle auto-terminate alarm; `stop_instance` terminates to save EBS. `_execute_spa_pipeline_sync` runs a 4-phase pipeline (A motion+CTF, B picking, C 2D classification, D ab-initio→refine→FSC→NU-refine→sharpen). QC gates fire inline via `_fire_qc_halt`/`_fire_qc_advisory`. `mock_mode` for tests.

## 6. Container resolution

`container_resolution.py` (126 lines) is a REST wrapper over Galaxy's `tool_util/deps/`. `ContainerRegistry.find_best_container_description` (`containers.py:357`; the `ContainerRegistry` class starts at L273) tries resolvers in order, first match wins: Explicit → ExplicitSingularity → CachedMulledDocker → CachedMulledSingularity → MulledDocker (quay.io) → MulledSingularity → BuildMulled*. **Note:** Nextflow tasks use the fixed ECR base image (§1); this resolver is the classic Galaxy tool-execution path.

## 7. Step parsing & outputs

`GET /api/nextflow/steps` → `get_nextflow_steps` (L6227) → `_parse_nextflow_steps` (`ai_assistant.py:659–862`), preferring DB metadata (`_steps_from_db_metadata` L6082) with a synthetic fallback (L6157). Parser strategies: (0) documented `// Steps:` markers (Bioconductor), (1) `process {…}` blocks, (2) numbered-comment, (3) nf-core DSL2 `include{…}`. Outputs reach the frontend via S3 listers `_list_s3_output_files` (L3618) and `_list_s3_work_output_files` (L3686, workDir fallback because publishDir cross-region writes often fail); presigned URLs via `/runs/{run_id}/output_files`.

## 8. SSE / progress

`_start_qc_monitor` (L3361) spawns a poller that tails `workflow-trace.txt` (`_parse_trace_progress` L3102) and `_sse_callback` (L3390) HTTP-POSTs `{invocation_id, event_type, data}` to **`{FRONTEND_URL}/internal/sse-inject`** (see [FRONTEND §4](../02-frontend/FRONTEND.md)). Event types: `workflow.phase_started/phase_completed`, `qc_gate_triggered`, `autoloop_gate_results`, `autoloop_update`, `chat_progress`. **`FRONTEND_URL` must match the host clients connect to** or events are dropped.

## 9. Workflow files & path resolution

- **`backend/biomni_workflows/nextflow_nfcore/subworkflows/`** — 34 domain dirs, **2,221 `main.nf`** total (bioconductor dominates; see [DOMAIN_MODULES §8](../04-domains/DOMAIN_MODULES.md)). **`backend/nf-core-modules/`** — upstream nf-core layout (94 subworkflows).
- **`nextflow_path` → real `.nf`:** `_resolve_nextflow_path` (L1495): absolute/relative first; then normalize logical aliases (`nfcore/subworkflows/<name>`, `nfcore/<pipeline>`, `biomni_nf/<domain>/<name>`, `nextflow_nfcore/<...>`); expand `.nf`/`main.nf`; search ordered `_candidate_bases` (L1447): `NEXTFLOW_SEARCH_ROOTS` env → backend root → `biomni_workflows/nextflow_nfcore[/subworkflows|/workflows]` → **`nf-core-workflows` (real downloaded pipelines) BEFORE `biomni_workflows/nfcore` display-only stubs** (the 2026-08-24 fix this branch is named for) → `nf-core-modules`. First existing `.nf` wins; a `drug_discovery↔pharmacology` alias retry follows.

## Cross-cutting invariants
1. Nextflow **head** = local subprocess; only tasks on Batch.
2. `RUN_STATE_STORE=redis` required or cross-worker orphan completion is silently inactive.
3. Cryo-EM bypasses Nextflow+Batch (EC2 + CryoSPARC API).
4. ADMET auto-loop is advisory — emits suggestions, does not auto-restart.
5. Real nf-core pipelines resolve before display-only stubs.

## Key files

| Path | Purpose | ~LOC |
|------|---------|------|
| `webapps/.../nextflow_executor.py` | Launch/track/finalize; Batch config; QC monitor; routes | 10,157 |
| `ai/runs/run_state_store.py` | Protocol + InMemory + Redis + factory | ~340 |
| `ai/runs/completion_poller.py` | Orphan-detection thread | ~206 |
| `ai/runs/orphan_finalizer.py` | Cross-worker completion | 312 |
| `qc_thresholds.json` | Evidence-graded threshold DB | 995 |
| `webapps/.../cryosparc_qc_gates.py` | Cryo-EM gates | 776 |
| `experiments/autoloop_bridge.py` + `admet_autoloop/{qc_evaluator,param_tuner}.py` | ADMET auto-loop + remediation | ~1,400 |
| `webapps/.../autofix3.py` + `ai/workflow_ops/autofix/` | Autofix API + agent + tools | ~10K |
| `webapps/.../cryosparc_executor.py` | EC2 + CryoSPARC 4-phase SPA | 2,510 |
