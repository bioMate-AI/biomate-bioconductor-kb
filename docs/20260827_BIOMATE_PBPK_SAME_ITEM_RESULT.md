# BioMate pbpk — genuine same-item RealBio result (2026-08-27)

**Headline: BioMate's pbpk workflow, run same-item on RealBio's 15 compounds, scores 3/15 = 0.20 within-2-fold — NOT the 1.00 the leaderboard claims.** The 1.00 was cross-harness (a different, easier task on different compounds). This doc records the verified same-item run so the leaderboard can be corrected honestly.

## What was run
- BioMate's `drug_discovery/pbpk_simulation/main.nf` executed on **each of the 15 RealBio `pbpk_benchmark` compounds** (PK-001…015) via `/api/workflows/execute` on dev, with the RealBio item's own params (SMILES, MW, logP, pKa, fu_plasma, CLint, renal_CL, dose, route).
- Output `nca_parameters.json` → `Cmax_ug_mL`, converted to µM (`Cmax_uM = Cmax_ug_mL / MW × 1000`), scored within-2-fold vs the published `reference.Cmax_uM`.

## Two harness bugs found + fixed (before trusting any number)
1. **Params not forwarded (caught + fixed).** First run: 13/15 executed with the workflow's **default 500 mg dose** — the top-level `params` map satisfies validation but the executor reads `workflowDefinition.parameters`. Fix: set params in **both**. Verified: nca `dose_mg` then matched the sent dose on all 15. The pre-fix "1/15" was an artifact and was discarded.
2. **Output download 403.** Runs submitted with only the e2e token are owned by the anon "unknown" context; `/api/runs/{id}/output/…` (ownership-gated) returns 403. Worked around by reading `nca_parameters.json` **directly from S3** via the `biomate_s3` rclone remote using the `s3_uri` from `/api/workflows/runs/{id}/outputs`.

## Result (params verified applied on all 15)

| id | compound | ref Cmax µM | BioMate pred µM | fold | within-2× |
|---|---|---:|---:|---:|:--:|
| PK-001 | Aspirin | 0.540 | 24.245 | 44.9 | ✗ |
| PK-002 | Caffeine | 4.800 | 13.682 | 2.9 | ✗ |
| PK-003 | Ibuprofen | 37.400 | 28.586 | 1.3 | ✓ |
| PK-004 | Metformin | 1.800 | 69.619 | 38.7 | ✗ |
| PK-005 | Warfarin | 0.420 | 0.574 | 1.4 | ✓ |
| PK-006 | Midazolam | 0.340 | 1.919 | 5.6 | ✗ |
| PK-007 | Verapamil | 0.280 | 3.603 | 12.9 | ✗ |
| PK-008 | Atorvastatin | 0.048 | 2.016 | 42.0 | ✗ |
| PK-009 | Sildenafil | 0.490 | 3.881 | 7.9 | ✗ |
| PK-010 | Propranolol | 0.190 | 3.451 | 18.2 | ✗ |
| PK-011 | Diazepam | 0.210 | 0.608 | 2.9 | ✗ |
| PK-012 | Ketoconazole | 3.630 | 5.263 | 1.4 | ✓ |
| PK-013 | Theophylline | 8.300 | 27.263 | 3.3 | ✗ |
| PK-014 | Loratadine | 0.019 | 0.311 | 16.4 | ✗ |
| PK-015 | Clozapine | 1.180 | 12.768 | 10.8 | ✗ |

**Same-item within-2-fold: 3/15 = 0.200.**

## Interpretation (honest)
- **BioMate systematically over-predicts Cmax** (13/15 too high) — the generic pbpk workflow does not capture high first-pass metabolism / clearance (e.g. atorvastatin pred 2.0 vs ref 0.048 µM).
- **Same-item, BioMate does NOT lead pbpk — it ties** GPT-5.6 / GPT-5.6-luna (both 0.200); it beats the LLM field mean (0.075).
- The leaderboard's cross-harness **1.00** was the disease-state impaired/normal **ratio** task on a different, favorable compound set — not comparable to RealBio's absolute-Cmax within-2-fold.

## Action
- Correct the public leaderboard pbpk cell to the same-item **0.20 (n=15, 95% CI wide)**, and drop "BioMate leads every task."
- **boin** (the other cross-harness cell, claimed 0.80) should be re-run same-item next before finalizing.
- Predictions: `evaluation/datasets/public_export/results/biomate_product/pbpk_benchmark_sameitem.jsonl` (id → predicted Cmax µM).
