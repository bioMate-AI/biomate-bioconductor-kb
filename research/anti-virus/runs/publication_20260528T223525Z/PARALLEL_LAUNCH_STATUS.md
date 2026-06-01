# Parallel compute launch — 2026-05-29

## Plan B (item 3)

| Step | Status | Run / artifact |
|------|--------|----------------|
| ANDV P0 QC (local) | **Done** | `plan_b_p0/andv_p0_mrna_validation_report.json` — **overall_pass: true** |
| 12819 spike P0 (Batch) | **Running** | run_id `aa91ff4a-9244-4242-bfc5-303ec42a1ffd` |
| 12867 NP PK (Batch) | **Running** | run_id `70aae8a8-e2d4-486e-8625-9e969270aab4` |
| Manuscript v1.1 | **Done** | `docs/MANUSCRIPT_PLAN_B_CODON_v1_0.md` |
| Figures | **Done** | `runs/manuscript_figures_v1/plan_b/` |

Poll Batch:
```bash
curl -s -H "X-API-Key: $(grep bootstrap_admin_api_key backend/config/galaxy.yml | awk '{print $2}')" \
  http://127.0.0.1:8081/api/nextflow/status/70aae8a8-e2d4-486e-8625-9e969270aab4
```

After 12867 completes, download `np_pk_results.json` to `plan_b_np_pk/` and re-run figures for Fig C5.

## Inhibitor (item 2)

| Job | Log | Notes |
|-----|-----|-------|
| Ensemble top-5 ZINC | `inh_ensemble_top5.log` | Run dir `science_sprint/runs/20260529T052440Z/track_inh_ensemble/` |
| GROMACS top hit (INH-01) | `gromacs_top_hit.log` | 5M steps, ligand `N=C(N)NC(=O)c1nccnc1N` |
| GROMACS aspirin control | `gromacs_aspirin_control.log` | 5M steps |

**Fix applied:** `track_inh_ensemble_docking.py` now downloads results when Batch reports `failed` but process status is `COMPLETED` (May 29 top-15 false failure).

ZINC150 reconcile: rigid Vina JSON exists at `zinc150_screen/vina/docking_autodock_vina_results.json`; driver `zinc150_vina_status.json` top-level `failed` was a polling artifact — Nextflow trace shows COMPLETED.
