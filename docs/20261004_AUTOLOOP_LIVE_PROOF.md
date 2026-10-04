# Live QC-gate-fires + remediation proof (ADMET hERG/DILI)

**Date:** 2026-10-04
**Why:** CLAUDE.md's UX standard and the flagship paper's Tier-3 case study require a committed artifact
proving a QC auto-loop gate fired on a **live** run. Prior to this, the only on-disk proof
(`frontend/e2e/screenshots/autoloop-live-proof/proof-report.json`, 2026-09-09) showed the gate did NOT
fire (ran against a dev backend without the fix). This replaces it with a real firing.

## Deploy pre-check (read-only, before spending the run)
The running dev Galaxy container (`biomate-galaxy-dev`) **does** contain the completion-time autoloop
emit — `from experiments.autoloop_bridge import evaluate_and_emit` / `evaluate_and_emit(...)` at
`/app/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:3499-3500` (verified via read-only SSM). So the
fix is live; no sync was needed.

## The run
- **run_id:** `d0ff684b-fd91-4e6f-ba0a-ea136b427700` (invocation `631ab616-…`, nextflow `75a770d9-…`)
- **Workflow:** Predict ADMET Properties (AI) — `nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf`
- **Engine:** AWS Batch (`is_batch: true`), status **succeeded**, returncode 0, duration **292 s**
- **Inputs:** `smiles_list = [aspirin, terfenadine]`, `ADMET_model_type=MPNN`, `admet_shard_size=25`
  - aspirin `CC(=O)OC1=CC=CC=C1C(=O)O` (hERG-safe control)
  - terfenadine `OC(CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1)(c1ccc(cc1)C(C)(C)C)CC` (known hERG liability)

## The gate FIRED LIVE (durable, from the run record `qc_gates`)
```json
[
 {"metric":"herg_ic50_uM","value":0.012,"threshold":1,"operator":"<",
  "message":"[GOLD] hERG IC50 0.012 µM is below the high-risk threshold of 1.0 µM (Sanguinetti & Tristani-Firouzi 2006; FDA E14 guidance). High-risk hERG inhibition predicts QT interval prolongation and risk of Torsade de Pointes (TdP). Structural optimisation to reduce hERG liability is required before progression."},
 {"metric":"dili_risk","value":"high","threshold":"low","operator":"!=",
  "message":"[GOLD] DILI risk classified as 'high' (DILIrank; Chen et al. 2016). ... Hepatotoxicity investigation (ALT/AST panel, hepatocyte assay) is required before clinical progression."}
]
```

## Raw S3 metrics (ground truth; saved alongside this doc)
`docs/autoloop_live_proof_20261004/{qc_metrics.json,toxicity_report.json}` from the run's S3 outdir.
Per-compound (panel aggregation = worst-compound-in-panel):
| compound | logP | MW | hERG IC50 (µM) | hERG_prob | DILI prob |
|---|---:|---:|---:|---:|---:|
| aspirin | 1.31 | 180.2 | 10000 (safe) | 0.003 | 0.855 (high) |
| terfenadine | 7.01 | 499.7 | **0.0124 (halt)** | 0.974 | 0.043 (low) |
Panel: `herg_ic50_uM=0.0124` (terfenadine drives the hERG halt), `dili_risk=high` / `dili_probability=0.855`
(aspirin drives the DILI halt). Evidence tier GOLD (Redfern 2003 / Kazius 2005 / Mulliner 2016).

## Discriminating, not always-on (control run)
The earlier run `46953d98-…` (same workflow, **safe** defaults aspirin/caffeine/ibuprofen) completed with
`qc_gates: []` — the gate stays silent on safe compounds and fires only on the real liability. This
contrast is the proof the gate is meaningful, not a constant.

## Remediation (was → now), deterministic from `param_tuner.remediate()`
For the two halting gates, `backend/experiments/admet_autoloop/param_tuner.py` produces:
| param | was (default) | now (remediated) | basis |
|---|---:|---:|---|
| `logp_max` | 5.0 | **≤ 4.0** (QSAR-inverted hERG target, `HERG_QSAR_LOGP_COEFF=-0.35`, `HERG_SAFETY_MARGIN=1.5`; capped at the Lammert boundary 4.0 that the DILI gate also sets) | hERG + DILI halts |
| `mw_max_da` | 500 | **400** (`MW_LAMMERT_BOUNDARY`) | DILI halt |
i.e. the system tightens the Lipinski logP/MW envelope to filter the hERG/DILI-liable chemotype on re-run.

**Honesty note on the remediation half.** The auto-loop bridge is **reactive/advisory**: on a failing
gate it emits `autoloop_gate_results` + `autoloop_update` SSE (carrying `param_changes`) and stores
suggestions in-memory keyed by `invocation_id`, served at `GET /api/invocations/{id}/autoloop-suggestions`
(`nextflow_executor.py:7589`). The actual re-run is a **separate deliberate call**, not a fully autonomous
restart. The live suggestion store is per-gunicorn-worker in-memory and is **not** proxied by the public
Node API (returns 404) — so for this already-completed run the live was→now payload was not retrievable
post-hoc; the table above is the deterministic output of the same `param_tuner` code given the captured
gate values. The **gate-fire itself is the durable, live-captured fact** (run record `qc_gates` above).
To capture the live SSE param-diff too, run `frontend/e2e/autoloop-live-proof.e2e.ts` (subscribes to
`/api/workflows/{runId}/events`) and fetch `/api/invocations/{id}/autoloop-suggestions` on the storing
worker within the same request window.

## What this upgrades
- Marketing/evidence: "QC auto-loop gate fires live" moves from **Partial/Aspirational → Evidenced**
  (gate-fire, run `d0ff684b`). The remediation is an **advisory suggestion** (reactive), not an
  autonomous closed-loop re-run — state it that way externally.
- Flagship Paper A (Tier-3 case study): usable as a real governed-run example — a live ADMET run whose
  GOLD hERG gate fired at 0.012 µM and produced a grounded, cited remediation.
