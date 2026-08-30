# 05 · Data & Databases

**Verified 2026-08-29** — every count below was produced by running the query on the checked-out tree.

---

## Datastore inventory

| Datastore | Tech | Holds | Where |
|-----------|------|-------|-------|
| **AI tools / workflow DB** | SQLite (FTS5 + sqlite-vec) | 4,057 workflows + 12,301 tools (enriched), cryo-EM RAG chunks, routing/learning tables | `backend/database/galaxy_ai_tools.db` (315 MB, gitignored; canonical on dev + S3 `db-backups/`) |
| **Main app DB** | PostgreSQL (Drizzle) | users/auth/MFA/Stripe, projects, sessions, messages, `workflow_executions`, billing fields, invites, instruments, download jobs | schema `frontend/shared/schema.ts`; migrations `frontend/migrations/*.sql` |
| **Long-Term Memory DB** | PostgreSQL (Drizzle, same cluster) | episodes, procedures, preferences, correction_log, project_knowledge, state facts | schema `frontend/shared/ltm-schema.ts`; migration `0012_ltm_schema.sql` |
| **Galaxy core ORM DB** | SQLite (dev) / Postgres (prod) | datasets, histories, jobs, galaxy_sessions, tools | `backend/database/universe.sqlite` (3 MB local, 187 tables) |
| **Redis (billing-shared)** | Redis (ElastiCache) | run-state hashes, billing monthly ledger, workflow-session, federated-query cache | `REDIS_URL` |
| **Benchmark / regulatory / broker** | SQLite | benchmark studies; IND/regulatory patterns; Celery broker (dev) | `benchmark_knowledge.db` (86 KB), `regulatory_skills.db` (45 KB), `control.sqlite` (60 KB) |
| **Object storage** | AWS S3 | Nextflow workdirs/outputs, cryo-EM & test data, DB backups, billing events | `biomate-nextflow-work`, `biomate-cryo-data`, `biomate-test-data`, `db-backups/`, … |

> **Stub warning corrected:** in *this* checkout, `backend/database/galaxy_ai_tools.db` is the **full 315 MB enriched DB**, not a stub. The genuine 0-byte stubs are `backend/data/galaxy_ai_tools.db`, `backend/galaxy_ai_tools.db`, `backend/data/workflows.db`, `backend/database/biomate.db`. A fresh clone gets the stub; pull the real DB from S3, never `--rebuild`.

---

## 1. AI tools / workflow DB — `galaxy_ai_tools.db`

**Counts (verified):** `workflows` = **4,057**, `tools` = **12,301**, `cryo_em_chunks` = 181. (CLAUDE.md's "2,455 / 34 domains" is stale.)

### `workflows` — key columns
`id` (PK), `name`, `filename` (UNIQUE), `description`, `annotation`, `tags` (JSON), `domain`, `workflow_json` (full `.ga`), `step_count`, `tools_used` (JSON), `source`, `format`, `executable`, `docker_image`, `category`, `input_types`, `output_types`, `annotation_v2`, `workflow_correctness_score`/`_verdict`, `workflow_json_v2`, `params_schema`, `real_exec_status`/`_at`/`_produced`/`_err`/`_provisional`, `step_metadata`, `qc_steps`, `visualization_tools`.

### `tools` — key columns
`id` (PK), `tool_id` (UNIQUE), `name`, `version`, `repo_owner`/`repo_name`, `category`, `parameters`, `inputs`/`outputs`, `requirements`, `edam_operations`/`edam_topics`, `scientific_context`, `scientific_context_v2` (+`_at`/`_verify_rate`), `nfcore_metadata`, `quality_score`, `priority_score`, `availability_status`, `container_info`, `galaxy_inputs`/`galaxy_outputs`/`galaxy_tool_state`, `embedding` (BLOB — semantic-search vector).

### Search indexes (all in-SQLite — no external FAISS)
- **FTS5:** `workflows_fts` (external-content over name/description/annotation/tags/domain/tools_used, kept in sync by `workflows_ai`/`workflows_au` triggers), `tools_fts` (porter unicode61), `cryo_em_protocols_fts`.
- **Vector:** `cryo_em_chunks_vec USING vec0(embedding float[384])` (sqlite-vec) for cryo-EM RAG; tool vectors live in `tools.embedding` BLOB; workflow vectors in `backend/database/galaxy_ai_workflow_embeddings.npz` (being retired in favor of DB-native BLOBs).

### Domains (39, verified counts)
transcriptomics 1693, genomics 750, epigenomics 262, proteomics 182, variant_calling 181, general 143, drug_discovery 122, systems_biology 108, single_cell 95, imaging 77, metagenomics 75, metabolomics 57, pharmacology 39, genetics 35, molecular_biology 33, immunology 25, bioimaging 24, microbiology 19, physiology 14, bioengineering 13, synthetic_biology 12, structural_biology 11, cryo_em 11, biochemistry 10, population_genetics 8, lab_automation 8, pathology 7, cancer_biology 7, spatial_transcriptomics 6, database 6, cell_biology 5, literature 4, immuno_oncology 3, glycoengineering 3, biophysics 3, multi_omics 2, cryo_et 2, rare_disease 1, other 1.

> The **domain count in this DB (39, `domain` column)** differs from the **subworkflow-folder count (34 dirs)** in [DOMAIN_MODULES §8](../04-domains/DOMAIN_MODULES.md) — they are two different groupings (indexed-workflow domain tag vs on-disk catalog folder), so both figures are correct in their own context.

Also in this DB: learning/telemetry tables — `chat_sessions`, `chat_messages`, `session_workflows`/`datasets`/`compressions`/`summary`, `user_interactions`/`patterns`/`domain_profiles`, `context_inferences`, `routing_cache`, `workflow_chains`, `workflow_phase_rationale`, `workflow_generation_audit`, `cryo_em_{tools,parameters,protocols,chunks}`, `schema_migrations`.

## 2. Main application DB (PostgreSQL / Drizzle)

### `frontend/shared/schema.ts` (1,573 lines) — core app

| Table | Purpose / key columns |
|-------|-----------------------|
| `users` | auth + identity + Stripe + MFA + Galaxy link — `id (uuid)`, `email`, `password`, `subscriptionTier`/`Status`, `stripeCustomerId`, `trial*`, `mfaSecret`/`Enabled`/`RecoveryCodes`, `galaxyUserId`/`ApiKey`/`Username`, `llmApiKeys (jsonb)`, `inviteCodeId` |
| `invite_codes` / `invite_code_uses` | beta invite gating |
| `experiments`, `feature_flags` | A/B config, runtime flags |
| `api_keys` | user-issued `bm_live_*` keys (SHA-256 hashed) |
| `audit_logs`, `output_access_log` | security/audit trail, output-access log |
| `workflow_executions` | **run tracking** — `id`, `userId`, `projectId`, `galaxyInvocationId`/`WorkflowId`/`HistoryId`, `workflowName`, `workflowDefinition`, `status` (new/queued/running/ok/error), `totalSteps`/`completedSteps`, timestamps |
| `execution_runs` | persistent run state (SSE/autoloop; the row the orphan-finalizer flips) |
| `ux_feedback`, `telemetry_events` | UX + product telemetry |
| `instruments` / `instrument_events` | lab-instrument connector config + events |
| `download_jobs` | async output-download jobs |

### `frontend/shared/ltm-schema.ts` (646 lines) — LTM / learning

| Table | Class | Purpose |
|-------|-------|---------|
| `ltm_users` | identity | expertise, workflow-gen mode, success counters |
| `projects` | core | domain/organisms[]/tissueTypes[]/conditions[]/dataModalities[], storagePath |
| `sessions` | core | summary, keyDecisions, conversationState, chatSessionId, tokens |
| `conversation_messages` | core | role, content, toolsUsed, thinking*, tokenCount |
| `user_preferences` | **learning** | preferenceType/Key/Value, learnedFrom, `confidence`, `usageCount` |
| `correction_log` | **learning** | suggested→corrected, userExplanation, appliedToFuture |
| `project_knowledge` | **learning** | knowledgeType, content, relevanceScore |
| `workflows` (LTM) | core | workflowJson, galaxyWorkflowId, executionId, success, outputDatasets[] |
| `project_episodes` | **learning (episodic)** | userQuery/response/intent, whatWorked/Failed/lessonsLearned[], importanceScore, outcomeSuccess |
| `project_procedures` | **learning (procedural)** | triggerPattern, steps, successRate, timesUsed, learnedFrom[] (episode IDs) |
| `conversation_state_facts`, `pending_tasks` | core | session facts + task tracking |

Learning-loop semantics are covered in [MEMORY_LEARNING](../07-memory-connectors/MEMORY_LEARNING.md).

## 3. Migrations (three independent systems)

1. **App Postgres — `frontend/migrations/`:** 25 `.sql` (`0000_add_auth_system` → `0020_project_members`; LTM = `0012_ltm_schema`). **Caveat:** the Drizzle journal (`meta/_journal.json`) records only 2 entries — the rest are applied out-of-band via manual/catch-up SQL, so the journal is **not** the source of truth for what's applied.
2. **Legacy SQLite learning — `backend/migrations/`:** 4 files (`003`/`004`/`005`) seeding the SQLite learning tables (`schema_migrations`).
3. **Galaxy core — `backend/lib/galaxy/model/migrations/`:** Alembic (Galaxy's own ORM).

## 4. Redis usage (four subsystems, one shared ElastiCache, all fall back to in-memory)

| Subsystem | File | Keys |
|-----------|------|------|
| Run-state store | `ai/runs/run_state_store.py` | `nextflow:run:{id}` hash + `:runs:active` set + `:{id}:pid` + `:{id}:completing` lock; opt-in `RUN_STATE_STORE=redis` |
| Billing realtime ledger | `ai/billing/core/realtime_cost_service.py` | `cost:{uid}:month:{YYYY-MM}:llm` and `:compute` hashes (`hincrbyfloat`/`hincrby`), ~35-day expiry |
| Workflow session | `ai/workflow_session.py` | `wfsess:{session_id}` (`setex`) |
| Federated-query cache | `ai/federated_query.py` | short-TTL cross-source query cache |

## 5. Other SQLite datastores under `backend/database/`

| File | Size | Contents |
|------|------|----------|
| `universe.sqlite` | 3.0 MB | Galaxy core ORM (187 tables) — dev/local Galaxy backing store |
| `benchmark_knowledge.db` | 86 KB | benchmark_studies/tasks/results/findings, decision_rules |
| `regulatory_skills.db` | 45 KB | IND/regulatory documents, narrative_patterns, pbpk_benchmarks |
| `control.sqlite` | 60 KB | Celery kombu broker (local dev) |

## 6. S3 buckets (by frequency)
`biomate-nextflow-work` (primary run workdir/outputs), `biomate-data`, `biomate-cryo-data`, `biomate-test-data`, `biomate-outputs`/`biomate-nextflow-outputs`, `biomate-nextflow-sandbox`/`-base`/`-queue`; billing plumbing `biomate-batch-billing`, `biomate-s3-billing-events`(+`-dlq`); `db-backups/` prefix (enriched-DB pull path).
