# ZINC600 top-5 ensemble docking — launch config

Prepared: 2026-06-04T18:44:33Z  
Dry-run: `science_sprint/runs/20260604T184433Z/track_inh_ensemble/`  
Live run (local BioMate `127.0.0.1:8081` → AWS Batch): `science_sprint/runs/20260605T025716Z/track_inh_ensemble/` — poll `/tmp/ensemble_z600_top5_live.log`

## Compounds

| Rank | Vina (kcal/mol) | SMILES |
| ---: | ---: | --- |
| 1 | -6.527 | `N=C(N)NC(=O)NC(=O)NC(=N)N` |
| 2 | -6.275 | `Nc1nc(=O)c2c([nH]1)N[C@H](O)C=N2` |
| 3 | -6.267 | `N=C(N)NC(=O)c1nccnc1N` |
| 4 | -6.099 | `C[C@@H]1CN[C@H]2NC(N)=NC(=O)[C@@H]2N1` |
| 5 | -6.065 | `N=C(N)NC(=O)NC(=N)N` |

## Run (local BioMate API + AWS creds)

```bash
# backend: backend/start_backend.sh  (needs AWS_SECRET_ACCESS_KEY)
python3 research/anti-virus/science_sprint/track_inh_ensemble_docking.py \
  --baseline-docking-json research/anti-virus/runs/publication_20260528T223525Z/zinc150_screen/vina/docking_autodock_vina_results.json \
  --top-n 5
```

After completion, reconcile:

```bash
python3 research/anti-virus/scripts/reconcile_ensemble_docking.py \
  research/anti-virus/science_sprint/runs/<TIMESTAMP>/track_inh_ensemble
```

## Results (2026-06-05 live run)

Run: `science_sprint/runs/20260605T025716Z/track_inh_ensemble/` (reconciled)

| Metric | Value |
|--------|-------|
| Conformers succeeded | **6/6** |
| Improved vs rigid (deposit-only) | **4/5** |
| Largest Δ | **−0.137** kcal/mol (rank 2 on 9P3Y) |
| INH-01 (rank 3) | **unchanged** (−6.267 on 9P3I) |

**Interpretation:** ensemble sensitivity only; does **not** promote Z600-R1 over INH-01. Prior ZINC150 top-5 ensemble remained 0/5 improved.
