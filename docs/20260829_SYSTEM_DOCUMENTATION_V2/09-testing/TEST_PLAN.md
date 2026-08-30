# 09 · Comprehensive Test Plan (module / function based)

**Verified 2026-08-29.** This plan is organized **by module**, and within each module **by function**. For every module it states: what exists today (with the real test file), the gaps, and the specific test cases the team should add. Use it as the work backlog for the upgrade cycle.

**Conventions used throughout:**
- **Test types:** `unit` (vitest / pytest, no network) · `integ` (real DB/API, local) · `e2e` (Playwright against dev) · `bench` (evaluation harness) · `smoke` (post-deploy curl).
- **Fixtures:** canonical e2e account `lifeifei163361@163.com`, bypass token `biomate-e2e-bypass-token-dev-only`, target `https://dev-public.biomate.ai`. One login + one project per harness (see the seven e2e-discipline rules in CLAUDE.md).
- **Priority:** P0 = release-blocking · P1 = important · P2 = nice-to-have.

---

## 0. Pre-sync gate (must pass before every `sync_to_dev.sh`)  {#pre-sync-gate}

From `docs/PRE_SYNC_CHECKLIST.md` — non-negotiable, stop-and-fix on first failure:

1. **TS type check** — `cd frontend && npx tsc --noEmit -p .`
2. **Vitest** — `cd frontend && npx vitest run` (~7s; skippable only for pure-docs commits)
3. **Python import smoke** (MANDATORY, non-skippable) — for any modified `backend/lib/galaxy/**/*.py`: `cd backend && PYTHONPATH=lib python3.9 -c "import galaxy.webapps.galaxy.api.<module>"` (catches PEP 604 union-on-3.9 that crash-looped Galaxy 2026-06-03)
4. **Domain integration test** — if the surface was touched (AfterRun → `scripts/test_afterrun_comprehensive.py`; `.nf` → phase-groups test; new route → curl)
5. **Sync + post-sync smoke** — `/api/version` (backend up) + asset size (frontend bundle)

**Upgrade action (P0):** add a **unified backend pytest runner to the pre-sync gate**. Today `run_tests.py` exists but pre-sync only import-smokes the backend — the ~55 `backend/tests/` + `ai/**/tests/` suites are never gated. Wire a fast subset (routing, executor py3.9-compat, QC gate reader, run-state) into the checklist.

---

## 1. Frontend — Express server & React client

**Existing:** vitest 35 server + 31 client suites (`frontend/vitest.config.ts`); Playwright ~100 files.

### 1.1 `routes.ts` (308 handlers) — `unit`+`e2e`
| Function/route group | Existing | Add |
|----------------------|----------|-----|
| `/api/chat/stream` (L5535) | `panel-and-chat-stream.e2e.ts`, `chat-costlog-verify.e2e.ts` | P1 — assert workflow-card emission for each of the 6 canonical intents (ADMET/RNA-seq/WGS/CryoEM/CRO/IND); assert `cost_log` POST fired |
| `/api/ai_assistant/generate_workflow` (L6448) | `run_routing.py` bench | P0 — route-conflict guard test (two `/internal/billing/llm_cost` registrants — see 6.1) |
| `/api/billing/*` catch-all proxy (L14783) | `billing-smoke.e2e.ts` | P1 — assert Node forwards, never implements (regression guard) |
| `/internal/sse-inject` (L4468) | (implicit) | P0 — inject a raw event, assert fan-out to a connected EventSource; assert drop-with-log when `FRONTEND_URL` host mismatches |

### 1.2 SSE pipeline (`galaxy-state-poller.ts`, `workflow-sse.ts`) — `unit`+`e2e`
- **Existing:** `workflow-notification-service.test.ts`, `panel-and-chat-stream.e2e.ts`.
- **Add (P0):** unit-test `detectStateChanges` emits `workflow_state`/`step_state`/`progress_milestone` on the right transitions; e2e observe **at least one idle→running→terminal transition in real time** (the UX-completeness CRITICAL requirement), for both the success and failure paths.

### 1.3 `nextflow-workflow-viewer.tsx` (3452 LOC) — `unit`
- **Existing:** `nextflow-workflow-viewer.test.tsx`, `execution-control-panel.qc-profile.test.tsx`, `workflow-artifact.qc-summary.test.tsx`, `parameter-dialog.test.tsx`, `step-output-preview.test.tsx`.
- **Add (P1):** per-state `data-status` assertions (idle/running/completed/failed) per the UX-completeness standard; QC-gate two-number display (measured vs threshold) color coding; auto-loop was→now diff render; step-file preview branches (image/table/FASTA/VCF/text).

### 1.4 Two-tree risk (`components/` vs `v2/`) — `unit`
- **Add (P2):** shared behavior contract tests so `v2/PhaseCard` and `components/phase-card` stay in sync until unified.

## 2. Backend AI assistant (`ai/ai_assistant.py`, search, routing)

### 2.1 `generate_workflow_unified` pipeline — `unit`+`bench`
| Stage (fn) | Existing | Add |
|------------|----------|-----|
| Intent classify (`classify_intent`, `UnifiedIntentRouter`) | `analyze-intent-uqu.test.ts`, `test_multi_task_classifier.py` | P1 — keyword-fast-path vs LLM-fallback boundary at conf 0.6 |
| Fast-path shortcuts (L4052) | partial | P1 — one assertion per shortcut (codon/docking/BOIN/cryosparc/ADMET/GEO/nf-core) returns the right workflow |
| Score routing (`_calculate_score`) | `test_nextflow_routing_runnable.py`, `run_routing.py` (≥80%) | P0 — **reclassify guardrail regression**: assert the 283 domain subworkflows are NOT penalized −8 (docking/admet/chipseq/cryoem lift); assert genuine nf-core pipelines still win |
| Disambiguation (`_detect_alt_method_enumeration`) | `test_disambig_alt_method_gate.py` | P1 — "DESeq2 vs edgeR" fires even at high confidence; ADMET bypass promotes `predict_admet_properties` |
| Chain lookup | `test_chain_*.py`, `chain-system-comprehensive.e2e.ts` | ok |

### 2.2 Workflow generation — `unit`
- **Existing:** `ai/tests/workflow_generators/` (propose-validate, 5 files), `run_workflow_generation.py`, RealBio `workflow_generation`.
- **Add (P1):** `NextflowComposer` 4-layer contract — L0 cache hit (Jaccard ≥0.75), L2 composable-vs-adhoc split, L4 syntax-validation strip-retry (max 2 LLM); assert emitted `.nf` parses and `include{}` paths resolve.

### 2.3 Search & embeddings — `unit`+`integ`
- **Existing:** `test_workflow_retrieval_semantic.py`, `test_wired_workflow_search.py`.
- **Add (P1):** FTS5-only fallback when the embed socket is down (`embed_client` timeout path); RRF k=60 tool-search ordering; BGE vs MiniLM model-load isolation.

### 2.4 Parameter extraction (`_extract_*`, `_infer_params_from_intent_llm`) — `unit`+`bench`
- **Existing:** `run_param_prefill.py` (≥70%), `parameter-dialog.test.tsx`.
- **Add (P0):** deterministic rule tests — genome alias map (GRCh38→hg38…), SRA regex (SRR/GSE/GSM/PXD), extension→param, SMILES paren-nesting; **guardrail** test that schema-invalid LLM params are dropped; `_build_prereq_validation` flags truly-missing required params.

### 2.4b Expert-skills persona layer — `unit` (currently UNTESTED)
- **Add (P1):** `Skill.matches_query` trigger regex fires for each of the 9 personas' triggers and not for unrelated queries; `POST /api/skills/detect` returns the right persona; `system_block` composition injects the persona into the prompt; `/api/skills/upload` hot-reload adds a skill.

### 2.5 LLM client & resolver — `unit`
- **Existing:** `llm-client.test.ts`, `llm_internal` relay.
- **Add (P0):** `resolve_model()` precedence (BYOK per-role → BYOK global → `BIOMATE_MODEL_<ROLE>` → `BIOMATE_MODEL` → config → role default → global); YAML fallback-chain exponential backoff; **fragmentation regression** — a lint/test asserting no NEW hardcoded model literals appear outside `model_resolver.py` (guards the debt from growing).

## 3. Workflow execution engine (`nextflow_executor.py`)

### 3.1 Launch/track/finalize — `unit`+`integ`
- **Existing:** `test_nextflow_executor_{future_annotations,python39_compat,generate_config,list_param_json,native_sra_skip}.py`, `test_nextflow_false_success.py`, `test_stuck_running_guard.py`, `test_nextflow_version_pin.py`.
- **Add (P0):** `_looks_like_false_success` / `_looks_like_false_failure` truth table (exit0-empty→failed; exit-nonzero-with-S3→succeeded; negative-RC→interrupted); reentrant-`RLock` no-self-deadlock test; semaphore 503 at cap.

### 3.2 Run-state persistence — `unit`+`integ`
- **Existing:** `ai/runs/tests/test_{run_state_store,redis_run_state_store,completion_poller,orphan_finalizer}.py`.
- **Add (P0):** **live cross-worker orphan-finalize e2e** on the real 4-worker gunicorn — the actual scenario the whole subsystem exists for is currently only unit-covered. Kill a head PID mid-run, assert the poller (another worker) finalizes and flips the Postgres `execution_runs` row + emits terminal SSE.
- **Add (P1):** factory falls back to InMemory (no crash) when `RUN_STATE_STORE` unset / Redis unreachable, and **logs a warning** so the silent-inactive case is observable.

### 3.3 QC gates & auto-loop — `unit`+`integ`+`e2e`
- **Existing:** `test_qc_{gate_reader,consistency,e2e_domains,edge_cases,evidence}.py`, `test_cryosparc_qc_gates.py`, `experiments/*_autoloop/tests/`, `autoloop-full-arc.e2e.ts`, `autoloop-toggle.e2e.ts`.
- **Add (P0):** **ADMET hERG gate fired LIVE on dev** — the gate has never fired on real dev data (loops run on truth data only). Submit a real high-hERG compound, assert halt + a was→now remediation (`logp_max` 5.0→4.71) reaches the UI.
- **Add (P1):** `param_tuner` remediation math unit tests (log10 gap step, DILI Lammert-2010 boundary, Ames strict); REGULATORY-vs-RISK_STRATIFICATION halt split.

### 3.4 Autofix — `unit`+`bench`
- **Existing:** `ai/workflow_ops/autofix/tests/` (integration, parameter_fixer, runner, path_b_trigger, llm_shim), `run_autofix_benchmark.py`, RealBio `autofix_benchmark`.
- **Add (P1):** `iterative_debugger` duplicate-error abort-after-2; risk-gate (LOW auto / MEDIUM confirm / HIGH manual); rollback restores state on a failed apply.

### 3.5 CryoSPARC executor — `unit`
- **Existing:** `test_cryosparc_{qc_gates,smart_params}.py`, `cryoem-capstone.e2e.ts`.
- **Add (P1):** `mock_mode` 4-phase pipeline ordering; instance auto-stop after terminal; CloudWatch idle-alarm set. (Real EC2 GPU runs stay manual/cost-gated per CLAUDE.md.)

### 3.6 `workflow_ops/` diagnostic-agent fleet — `unit` (currently UNTESTED)
The 5 diagnostic agents (`LogAnalysisAgent`, `RootCauseAnalysisAgent`, `ResourceOptimizationAgent`, `ParameterConfigAgent`, `NetworkDiagnosticAgent`) + `agent_factory` + support modules (`auto_healer`, `comprehensive_log_analyzer`, `samplesheet_generator`, `workflow_restarter`, `dataset_resolver`) have **no test line today** — a whole failure-diagnosis product surface with zero coverage.
- **Add (P1):** `agent_factory` builds each agent type; each agent's diagnosis on a fixed captured failure log yields the expected category; `samplesheet_generator` produces a valid samplesheet; `workflow_restarter` resumes from `resume_from_run_id`.

## 4. Domain modules

| Module | Existing | Add |
|--------|----------|-----|
| Drug discovery / GP-Pareto | `test_mrsd_calculator.py`, `drug-dev-boilerplate-gate.test.ts`, `personalization-drug-discovery.test.ts` | P1 — `bayesian_optimizer` Pareto-front + hypervolume + Tanimoto-diversity on a fixed toy set |
| ADMET workflow | `run_admet_benchmark.py` (≥70%) | P0 — real Batch run of `pharmacology/predict_admet_properties` producing `toxicity_report.json` (see 3.3) |
| PBPK | `run_pbpk_benchmark.py` (≥60%), `20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md` | P1 — `pbpk_auc_fold_error` gate vs `auc_observed`; population-scaling branches |
| IND / regulatory | `ai/drug_discovery/tests/test_ind_*.py`, `test_regulatory_*.py`, `run_ind_gold_standard*.py` | P1 — §2.6.1 numeric-faithfulness guardrail (MRSD injected, not hallucinated); 21 CFR 11 e-sign TOTP + hash-chain `verify_chain()` |
| Cryo-EM knowledge | `test_cryoem_{rationale,chains}.py`, `test_knowledge_recall.py` | P1 — `detect_sample_class` (keyword + BGE centroid); `get_parameters_for_mw` binning |
| Multi-omics | `scripts/gate1/gate2_alignment_qc_*.py`, `multiomics_metric_harness.py` | P1 — `method_selector` shape→method (MOFA2/SNF); **Gate-1 over-correction detector on gold (GO)** still unrun |
| ML training | `ai/ml_training/tests/` (ludwig/sklearn/chemprop, `test_real_*_e2e.py`) | ok; P2 — TRL DPO/GRPO smoke |
| Research agent | `test_ai_assistant_api_citations.py`, `research-paperqa-flows.e2e.ts`, `run_hallucination_audit.py` | P0 — **anti-confab guard**: 0 mismatched citations when retrieval returns papers; graceful "insufficient evidence" when it returns 0 (no invented DOI/PMID) |

**Missing canonical-journey e2e (P1):** two of the six flagship use cases are not asserted end-to-end (only their sub-modules are unit-tested):
- **CRO compliance:** "create campaign → attach ADMET results → export compliance package" — assert the exported CSV/package artifact downloads and the hERG gate in `cro_submission_export` fires.
- **Drug-discovery IND:** "PBPK + clinical trial → generate §2.6.1 narrative → download DOCX" — assert the DOCX artifact exists and carries the injected (non-hallucinated) MRSD numbers.

## 5. Data & databases

- **Existing:** `migration-integration.test.ts`, `test_data_source_registry.py`.
- **Add (P1):** schema-drift test — assert `agentic_memory.py` (SQLAlchemy) and `ltm-schema.ts` (Drizzle) define the same LTM columns; **migration-applied assertion** independent of the (unreliable) Drizzle journal — verify all 25 `.sql` are actually applied on a fresh Postgres.
- **Add (P2):** DB-count canary — a nightly check that dev `galaxy_ai_tools.db` still has ≥4,057 workflows / ≥12,301 tools (catches an accidental `--rebuild` wiping enrichment).

## 6. Billing, auth, sandbox

### 6.1 Billing — `unit`+`e2e`
- **Existing:** `ai/billing/tests/test_{billing,billing_edge_cases,billing_regression,lago_gate}.py`, `billing-guards.test.ts`, `tier.test.ts`, `billing-smoke.e2e.ts`.
- **Add (P0):** `check_and_reserve` raises 402 at limit; quota-middleware returns 402/429 correctly; **route-conflict test** for the double `/internal/billing/llm_cost` registration (assert which one wins and that cost is recorded exactly once).
- **Add (P1):** `lago_enabled()` OFF → `ensure_quota_set` uses `DEFAULT_PLAN_LIMITS`; fail-closed 503 when `X-Internal-Key` unset.

### 6.2 Auth & provisioning — `unit`+`e2e`
- **Existing:** `auth-service.test.ts`, `auth-fixes-20260612.test.ts` (register round-trip), `auth-stale-key-downgrade-20260826.test.ts`, `cold-refresh-recovery.test.ts`, `encryption.test.ts`, `auth-flows-smoke.e2e.ts`, `auth-trust-matrix.e2e.ts`, `security-cross-user-isolation.e2e.ts`.
- **Add (P1):** `provisionGalaxyUser` retry/backoff + stale-key re-provision; e2e-bypass grants **only** the subscription waiver (identity still required — assert 401 without JWT even with the bypass header).

### 6.3 Sandbox — `unit`
- **Existing:** `test_connector_sandbox.py`; docs `20260819_SANDBOX_MODE_*`.
- **Add (P1):** `validator.py` all 15 rules block; `filter_container_env` drops every secret pattern; `validate_head_argv` rejects `--privileged`/host-net/root-UID/docker.sock and forces `runsc`. **Gate is default-off, so these are pure unit tests — no infra needed.**

### 6.4 Interactive tools — `unit`+`e2e`
- **Existing:** `interactive-launcher.test.tsx`, `interactive-tools.e2e.ts`, `interactive-autoselect-serve.e2e.ts`.
- **Add (P2):** `/interactive/<token>` WS frame-type preservation (TEXT vs BINARY) unit test; format→tool auto-select map; **file-tree input wiring** (deferred feature — track).

## 7. Memory & learning

- **Existing:** `test_wired_agentic_memory.py`, `memory-trust-matrix.e2e.ts`, `run_memory_benchmark.py`, `ltm-session-bridge.test.ts`.
- **Add (P0):** **emergent-procedure distillation** — this is a *stub* today (`consolidateEpisodes` detects ≥3 but never writes). Once wired, test that 3 successful same-intent episodes create a `project_procedures` row and that `record_usage` updates `success_rate`.
- **Add (P1):** preference reinforcement caps at 1.0 (+0.1 step); correction is prepended to the next intent.

## 8. Connectors / MCP

- **Existing:** `test_connector_live.py`, `test_instrument_connectors.py`, `connectors-dialog.e2e.ts` (live tests skip without creds).
- **Add (P1):** `tools_manifest.py` schema validity for all 24 tools (unit, in the connector repo); OAuth 2.1 scope enforcement (a `runs:read` token cannot call `run_workflow`).

## 9. Benchmarks (`evaluation/`) — capability gates

All present with runners; targets from CLAUDE.md. **These are capability gates, not pass/fail unit tests** — run on a cadence, fix BioMate (not the benchmark) when a score drops.

| Benchmark | Runner | Target |
|-----------|--------|-------:|
| param_prefill | `run_param_prefill.py` | ≥70% |
| routing | `run_routing.py` | ≥80% |
| biomni_eval1 | `run_biomni_eval1.py` | ≥70% |
| admet_benchmark | `run_admet_benchmark.py` | ≥70% |
| pbpk_benchmark | `run_pbpk_benchmark.py` | ≥60% |
| boin_benchmark | `run_boin_benchmark.py` | ≥70% |
| stability | `run_stability.py` | ≥90% |

**RealBio flagship** — `evaluation/datasets/public_export/` (`run_all.py`, `run_biomni_realbio.py`, `score.py`, leaderboard). **Caveat (P0 hygiene):** live-exec tasks skip without creds, and some 2026-08 immune-LLM/VCC scores are **leakage-suspect** (`docs/20260828_IMMUNE_LLM_AND_VCC_CODE_AUDIT.md`) — do not cite those in product decisions until re-run.

---

## Coverage matrix (subsystem × status)

| Subsystem | Present | File(s) | Gap / action |
|-----------|---------|---------|--------------|
| Auth / token | unit+e2e | `auth-*.test.ts`, `auth-flows-smoke.e2e.ts` | Strong |
| Project module | unit+e2e+shell | `project-routes.test.ts`, `project-*.e2e.ts` (9), `audit_project_framework.sh` | Strong |
| Chat / intent / routing | unit+e2e+bench | `analyze-intent-uqu.test.ts`, `run_routing.py`, `test_nextflow_routing_runnable.py` | Good; add reclassify-guardrail regression (P0) |
| Workflow generation | unit+bench | `ai/tests/workflow_generators/`, `run_workflow_generation.py` | Good; add composer 4-layer contract |
| Param extraction | unit+bench | `run_param_prefill.py`, `parameter-dialog.test.tsx` | Add deterministic rule tests (P0) |
| Nextflow executor | unit | `test_nextflow_executor_*.py`, `test_nextflow_false_success.py` | Good (unit); **no live-Batch gate** |
| Run-state / orphan finalize | unit | `ai/runs/tests/` | **No live cross-worker e2e (P0)** |
| QC gates / auto-loop | unit+e2e+experiments | `test_qc_*.py`, `autoloop-full-arc.e2e.ts` | **hERG gate never fired live (P0)** |
| Autofix | unit+bench | `autofix/tests/`, `run_autofix_benchmark.py` | Good |
| Billing / quota | unit+e2e | `ai/billing/tests/`, `billing-smoke.e2e.ts` | Add route-conflict + 402/429 (P0) |
| Drug discovery / IND | unit | `ai/drug_discovery/tests/` (~18) | Good |
| ADMET | unit+bench+e2e | `experiments/admet_autoloop/tests/`, `run_admet_benchmark.py` | **Live gate-firing unverified (P0)** |
| PBPK / BOIN | bench | `run_pbpk_benchmark.py`, `run_boin_benchmark.py` | Good offline; real-exec thin |
| CryoEM | unit+e2e | `test_cryoem_*.py`, `cryoem-capstone.e2e.ts` | Capstone only |
| WGS / variant | e2e | `wgs-capstone.e2e.ts` | Single capstone |
| **Proteomics / metabolomics / ChIP-seq / single-cell / spatial** | **DB-indexed only** | — | **NO real end-to-end run evidence (P1)** |
| Chains | unit+e2e | `test_chain_*.py`, `chain-system-comprehensive.e2e.ts` | Good |
| Interactive tools | unit+e2e | `interactive-launcher.test.tsx`, `interactive-tools.e2e.ts` | File-tree input wiring deferred |
| Connectors / instruments | unit | `test_connector_live.py` (skips w/o creds) | Add manifest + scope tests (connector repo) |
| Research / citations | unit+e2e+bench | `test_ai_assistant_api_citations.py`, `run_hallucination_audit.py` | Add anti-confab 0-mismatch gate (P0) |
| Memory | unit+e2e+bench | `test_wired_agentic_memory.py`, `run_memory_benchmark.py` | Procedure distillation is a stub (P0 once wired) |
| ML training | unit+real-e2e | `ai/ml_training/tests/` | Good |
| Backend suite orchestration | scattered | `ai/run_tests.py` | **No CI-gated backend pass-count (P0)** |
| Frontend demos | screenshots (no assertions) | `e2e/*.demo.ts` (~30) | **Not regression gates (P2)** |

> `backend/lib/galaxy_test/**` (~200 files) is **inherited upstream Galaxy** coverage, not BioMate product tests.

---

## Prioritized backlog (do these first)

**P0 (release-blocking gaps):**
1. Unified backend pytest runner in the pre-sync gate (§0).
2. Live cross-worker orphan-finalize e2e on 4-worker gunicorn (§3.2).
3. ADMET hERG gate fired live on dev with a real remediation (§3.3, §4).
4. Reclassify-guardrail routing regression test (§2.1).
5. `resolve_model()` precedence + no-new-hardcoded-literals guard (§2.5).
6. Billing route-conflict + 402/429 enforcement (§6.1).
7. Research anti-confab 0-mismatch citation gate (§4).
8. Deterministic param-extraction rule tests + schema guardrail (§2.4).

**P1:** SSE real-time transition e2e (§1.2); composer 4-layer contract (§2.2); expert-skills persona coverage (§2.4b); autofix risk-gate/rollback (§3.4); **workflow_ops diagnostic-agent fleet — currently zero coverage (§3.6)**; IND numeric faithfulness + **CRO/IND full canonical-journey e2e** (§4); sandbox validator/env-filter units (§6.3); memory reinforcement (§7); no-run omics domains — at least one real Batch run each for proteomics/metabolomics/ChIP-seq/single-cell/spatial (§coverage).

**P2:** two-tree contract tests (§1.4); demos → assertions (§coverage); interactive file-tree wiring (§6.4); DB-count canary (§5).
