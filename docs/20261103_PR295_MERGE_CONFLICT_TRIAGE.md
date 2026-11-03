# Making PR #295 mergeable: conflict triage (2026-11-03)

PR #295 (`cursor/tutorial-live-recording-and-report-editing-4ea7` into `integration/next-phase`) is marked conflicting. This is the result of a trial merge of the base into the branch in a throwaway worktree (nothing was pushed, the trial was aborted).

**Size.** Merge-base 2026-09-04 (`2b11dbc4e`); the branch is 3,185 commits ahead and 236 behind. The trial merge conflicts in **31 files, 114 hunks**.

**Rule used to separate safe from manual.** If one side's file is byte-identical to an earlier version of the same file in the other side's history since the merge-base, the other side adds nothing newer and the file can be taken whole. `scripts/merge_conflict_triage.py <other-ref> [--apply]` implements it and only ever applies those provable cases.

| Result | Files | Hunks |
|---|---|---|
| TAKE_OURS (base side is an older version of ours) | 9 | 52 |
| TAKE_THEIRS (ours is an older version of the base side) | 1 | 1 |
| MANUAL (genuine divergence) | 21 | 61 |

The take-ours files include the three that carry the most hunks (`assay_schema.py` 16, `assay_ingestion.py` 13, `auto_retrain.py` 12). The base side holds a "product-only port" of commit `400aeffb7`, which this branch has in full plus a later in-flight commit (`1db223db8`), so taking ours loses nothing.

## Per-file table (hunks; commits touching the file on ours / theirs since the merge-base; whether this session touched it)
| Class | Hunks | Commits ours/theirs | This session | File |
|---|---|---|---|---|
| MANUAL | 9 | 94 / 31 | yes | `frontend/server/routes.ts` |
| MANUAL | 8 | 23 / 2 |  | `frontend/client/src/components/app-sidebar.tsx` |
| MANUAL | 6 | 46 / 13 | yes | `frontend/server/galaxy-assistant.ts` |
| MANUAL | 5 | 40 / 28 |  | `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` |
| MANUAL | 5 | 42 / 6 |  | `frontend/client/src/components/nextflow-workflow-viewer.tsx` |
| MANUAL | 4 | 8 / 3 | yes | `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` |
| MANUAL | 3 | 4 / 1 |  | `backend/lib/galaxy/ai/drug_discovery/api_router.py` |
| MANUAL | 3 | 22 / 4 |  | `frontend/client/src/components/chat-interface.tsx` |
| MANUAL | 3 | 25 / 3 |  | `frontend/client/src/components/chat-with-artifacts.tsx` |
| MANUAL | 2 | 24 / 1 |  | `frontend/client/src/components/chat-input.tsx` |
| MANUAL | 2 | 2 / 3 |  | `frontend/client/src/lib/i18n.ts` |
| MANUAL | 2 | 2 / 1 |  | `frontend/server/s3-client.ts` |
| MANUAL | 1 | 3 / 7 |  | `backend/docker/biomni-tools/Dockerfile` |
| MANUAL | 1 | 22 / 5 |  | `backend/lib/galaxy/ai/ai_assistant.py` |
| MANUAL | 1 | 1 / 3 |  | `backend/lib/galaxy/ai/billing/api/billing_router.py` |
| MANUAL | 1 | 2 / 4 |  | `backend/lib/galaxy/ai/llm_client.py` |
| MANUAL | 1 | 6 / 2 |  | `backend/lib/galaxy/jobs/qc_trace_monitor.py` |
| MANUAL | 1 | 2 / 1 |  | `frontend/Dockerfile` |
| MANUAL | 1 | 21 / 2 |  | `frontend/client/src/components/chat-message.tsx` |
| MANUAL | 1 | 9 / 2 |  | `frontend/client/src/pages/project-detail.tsx` |
| MANUAL | 1 | 35 / 1 |  | `frontend/client/src/v2/AfterRunReport.tsx` |
| TAKE_OURS | 16 | 3 / 1 |  | `backend/lib/galaxy/ai/drug_discovery/assay_schema.py` |
| TAKE_OURS | 13 | 2 / 1 |  | `backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py` |
| TAKE_OURS | 12 | 2 / 1 |  | `backend/lib/galaxy/ai/drug_discovery/auto_retrain.py` |
| TAKE_OURS | 4 | 3 / 1 | yes | `research/guangzhou_all_atom/cyclic_llm/knowledge_liability_flags.py` |
| TAKE_OURS | 2 | 2 / 1 |  | `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py` |
| TAKE_OURS | 2 | 5 / 2 |  | `docs/20261005_ONPREM_SCOPED_DEPLOYMENT.md` |
| TAKE_OURS | 1 | 3 / 1 |  | `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/predict_binding_affinity_protein_1d_sequence/main.nf` |
| TAKE_OURS | 1 | 2 / 1 |  | `backend/lib/galaxy/ai/drug_discovery/tests/test_campaign_learning_loop.py` |
| TAKE_OURS | 1 | 2 / 1 |  | `docs/20261005_AGENT_ENG_FIXES.md` |
| TAKE_THEIRS | 1 | 1 / 2 | yes | `docs/20261006_CHAIN_NAME_LEAK_AND_HANG_ROOTCAUSE.md` |

## What the manual files look like
Read in detail (three of the one-hunk files), each is a real design difference, not a textual accident:
- `billing_router.py`: two different SQL designs for the API-key lookup (this branch excludes the master key and orders by id; the base side selects by `deleted` flag only).
- `llm_client.py`: two different on-prem routes (this branch routes to `generate_local` when `local_only()`; the base side routes a set of direct providers through an OpenAI-compatible call).
- `qc_trace_monitor.py`: inline boto3 client with a list of report names (this branch) versus a shared `make_s3_client()` helper (base side).
The others are large frontend files edited heavily on both sides (`routes.ts` 94 commits ours, 31 theirs; `galaxy-assistant.ts` 46/13; `app-sidebar.tsx` 8 hunks; `nextflow-workflow-viewer.tsx` 42/6). Four of the manual files are ones this session also edited: `routes.ts`, `galaxy-assistant.ts`, `workflow_chain.py`, `knowledge_liability_flags.py` (the last is TAKE_OURS).

## Recommended procedure
1. In a separate worktree: `git merge --no-commit origin/integration/next-phase`, then `python3 scripts/merge_conflict_triage.py origin/integration/next-phase --apply` (resolves the 10 safe files).
2. Resolve the 21 manual files with their owners (backend: billing, LLM client, executor, QC monitor, Dockerfiles; frontend: chat components, sidebar, viewer, routes). Do not resolve by "take one side" for the three design differences above.
3. Run the pre-sync checklist (`tsc`, vitest, python3.9 compile, chain lint) on the merge result before pushing; then update #295.
4. A conflict-free merge does not make a 14,000-file PR reviewable; consider landing it in slices (for example the drug-discovery and chain/target-ID backend first, then UI).

## Progress (2026-11-03): four manual files resolved, merge kept in a worktree
The in-progress merge is kept (not committed, not pushed) at `/Users/kky/biomate-merge-295` on local branch `merge-295-wip`. State there: the 10 mechanical files plus four manual files are resolved and staged; 17 files remain.

| File | Resolution | Pinned by |
|---|---|---|
| `billing_router.py` | Combined both fixes: keep the branch's master-key exclusion and newest-first order, use the base side's PostgreSQL-safe boolean `deleted`. The query is built in a helper `_existing_active_key_query` and the master-key clause is added only when a key is configured, so no untyped NULL parameter is sent. | real SQLite checks in `backend/tests/test_merge295_resolutions.py` |
| `llm_client.py` | `generate_async` order: `local_only()` (branch) first, then the on-prem direct providers (base), then the fallback chain. | source-order test |
| `nextflow_executor.py` (5 hunks) | Docking normalization block and its call kept (branch only). QC gate: the base side's preprocessing path first, then the branch's generic S3 reconstruction instead of the base side's bare `return []`, then CryoEM. Local output listing: both sides had fixed "local output links go through an S3-only endpoint" differently; kept the branch's link scheme (pinned by `test_nextflow_local_output_downloads.py`) and added the `rel_path` / `local_path` fields the base side's frontend reads. The base side's `/outputs/local-download` endpoint and lister stay in the file, unused by the listing: two mechanisms for one job; retire one once the owners agree. | tests plus the two existing executor test files (16 pass) |
| `workflow_chain.py` | Four independent additions: stricter rescue comment, DAG dispatch and execution-mode fields (branch), single-workflow chain naming comment (base). The binding check and transform wiring survived (6 and 1 references, same as before the merge). | compile; reference counts |

Verified: `py_compile` under python 3.9 for every resolved file, 16 backend tests. Not verified: the merged tree as a whole (the frontend and four more backend files are unresolved, so nothing can be imported or built yet); the billing helper against a real PostgreSQL.

**Still unmerged (17):** `Dockerfile`, `ai_assistant.py`, `api_router.py`, `qc_trace_monitor.py`, `Dockerfile`, `app-sidebar.tsx`, `chat-input.tsx`, `chat-interface.tsx`, `chat-message.tsx`, `chat-with-artifacts.tsx`, `nextflow-workflow-viewer.tsx`, `i18n.ts`, `project-detail.tsx`, `AfterRunReport.tsx`, `galaxy-assistant.ts`, `routes.ts`, `s3-client.ts`
