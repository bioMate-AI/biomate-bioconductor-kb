# INH Top-15 Ensemble Docking — In Flight

**Started:** 2026-05-29T00:30:02Z  
**Run dir:** `research/anti-virus/science_sprint/runs/20260529T003002Z/track_inh_ensemble/`  
**Log:** `inh_ensemble_top15.log`

## Design

| Parameter | Value |
|-----------|--------|
| Compounds | Top **15** from ZINC150 rigid 9P3I screen (INH-01 … INH-15) |
| Baseline JSON | `zinc150_screen/vina/docking_autodock_vina_results.json` |
| Conformers | **6** (top_pocket, 9P3I, 9P3Y, 9P3X, 9P3L, 9P3M) |
| Batch jobs | 6 sequential Vina runs × 15 ligands each |
| Per-job timeout | 4 h |

## Rigid baseline (9P3I) — top 3 for reference

| ID | Best rigid (kcal/mol) |
|----|----------------------|
| INH-01 | −6.267 |
| INH-02 | −5.881 |
| INH-03 | −5.678 |

## Monitor

```bash
tail -f research/anti-virus/runs/publication_20260528T223525Z/inh_ensemble_top15.log
```

## When complete

Results: `science_sprint/runs/20260529T003002Z/track_inh_ensemble/ensemble_results.json`  
Summary: `.../ensemble_summary.md`

Compare `ensemble_best_affinity_kcal_mol` vs rigid baseline per compound; expect 9P3Y (or similar) to improve scores as in the May 27 demo run (−1 to −1.3 kcal/mol on aspirin).
