# 2026-11-13 — ML training Findings ignored `metrics.json` (architecture fluff)

## Session

- URL: https://dev-public.biomate.ai/?session=chat-1794589821204-kwkyrwqu5
- Title: Train a potency predictor on our in-house assay…
- Workflow: `potency predictor` (`ml_training` / `ml_training/chemprop_train.nf`, Ludwig tabular)
- Run: `727de1b4-5bed-4409-92ca-d7ba10a7f46e` (completed)
- Outputs prefix: `s3://biomate-nextflow-work/nextflow/outputs/37942b0f-…/042dc0da/`

## User verdict

> Things went well except that the summary had a poor finding, the report sucks, too.
> They don't know where to read the most important info of this task… Everything clearly listed in outputs.

## What Outputs already had (the real answers)

| Artifact | Facts |
|----------|-------|
| `results/metrics.json` | **test_mae = 0.792**, **val_mae = 0.943**, gate status |
| `results/artifact/manifest.json` | same MAE + scaffold split `bemis_murcko_scaffold` train/val/test = 1211/151/151 |
| `training_progress.json` | best-checkpoint **R²** test 0.37 / val 0.45 / train 0.30 |

## What Findings / report showed (wrong)

`output/findings_data.json` led with Ludwig combiner architecture (concat / ReLU / output_size 300) and descriptor means (MolLogP, MolWt, …). Caveats claimed *"No model training or validation performance metrics are present"* — false. Next steps told the user to go retrieve the metrics that were already in Outputs.

## Root cause

1. Findings for this path went through the **LLM** sampler, not a deterministic parser.
2. Sampling ranked many JSON files similarly; Ludwig bookkeeping (`model_hyperparameters.json`, `training_set_metadata.json`) and a mislabeled `qc_events.json` crowded the context.
3. The LLM narrated architecture + feature stats and **ignored `metrics.json`**.
4. The bad sidecar was then **cached on S3**, so every reopen re-served fluff without regenerating.
5. Report download for Batch runs only rendered from in-memory cache (often empty) — not the S3 sidecar the Findings tab uses.

## Fix (rule first, LLM second)

| Change | Where |
|--------|--------|
| Deterministic `parseMlTrainingFindings` from `metrics.json` (+ optional `training_progress` R², `manifest` split) | `frontend/server/ml-training-findings.ts` |
| Wired into `preProcessForFindings` for `isModelTrainingRun` / name heuristics — **skips LLM** when metrics parse | `frontend/server/routes.ts` |
| Rank `metrics.json` / `manifest.json` / `training_progress.json` first; demote Ludwig hyperparams / false QC | `_resultScore` in findings gatherer |
| Refuse fluff sidecars (`looksLikeMlTrainingFluff`) → regenerate | local disk, S3, and in-memory cache gates |
| Report download renders Key Results **table** from cache **or S3 sidecar** | `/findings/report` |
| Unit tests with the live potency metrics payload | `frontend/server/ml-training-findings.test.ts` |

## How to verify

1. Hard-refresh the session (or `GET /api/workflows/runs/727de1b4-…/findings?regen=1` as the owning user).
2. Findings summary must lead with **test MAE / validation MAE**; Key Results table sourced from `metrics.json`.
3. Download report must show the same Key Results table (not combiner fluff).
4. `cd frontend && npx vitest run server/ml-training-findings.test.ts`

## Verification 2026-11-13 (continue/test)

| Check | Result |
|-------|--------|
| Live `build-info.json` | `429c3dbc…` (was `562908a3`) — **PASS** (`a41a9a76` still ancestor). Class follow-up: `docs/20261113_FINDINGS_CLASS_AUDIT_METRICS_FIRST.md` |
| FE image symbols | `/app/dist/index.js` contains `ml-training-metrics-v1` (1) + `looksLikeMlTrainingFluff` (6) — **PASS** |
| Unit + related | `ml-training-findings.test.ts` **5/5**; `findings-figures.test.ts` **6/6**; `tsc --noEmit` exit 0 |
| S3 sidecar | `…/042dc0da/output/findings_data.json` summary leads with test MAE=0.7920 / validation MAE=0.9433; `evidence_version=ml-training-metrics-v1`; no combiner/MolLogP fluff — **PASS** |
| Report (render path) | Same Key Results table from sidecar → `frontend/e2e/execshots/ml-findings-verify/report_from_sidecar.md` — **PASS** |
| Authenticated `/findings` as E2E fixture | **403** — run owned by `drugtest@biomate.dev` (`user_id=37942b0f-…`), not `lifeifei163361@163.com`. No stored password for owner; did not invent one. |

Evidence dir: `frontend/e2e/execshots/ml-findings-verify/` (`s3_findings_data.json`, `s3_metrics.json`, `report_from_sidecar.md`).

**S3 sidecar healed** (score-first + R²). Class-wide code follow-up committed; sync ships refuse-hollow / descriptor cutover / chip UX.

## Open

- Existing bad sidecars for other ml_training runs heal on next Findings open (fluff detector → regen).
- Gate measured value in this run was val_mae with `no_gate_configured`; summary still prefers explicit test/val MAE keys.
- Owner-authenticated UI/API screenshot for this session needs `drugtest@biomate.dev` credentials (not the E2E fixture).
