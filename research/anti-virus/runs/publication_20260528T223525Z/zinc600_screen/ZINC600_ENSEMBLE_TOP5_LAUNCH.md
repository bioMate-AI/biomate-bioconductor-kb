# ZINC600 top-5 ensemble docking — launch config

Prepared: 2026-06-04T18:44:33Z  
Dry-run validated: `science_sprint/runs/20260604T184433Z/track_inh_ensemble/` (6 conformers × 5 compounds; **Galaxy API required** for live scores)

## Compounds

| Rank | Vina (kcal/mol) | SMILES |
| ---: | ---: | --- |
| 1 | -6.527 | `N=C(N)NC(=O)NC(=O)NC(=N)N` |
| 2 | -6.275 | `Nc1nc(=O)c2c([nH]1)N[C@H](O)C=N2` |
| 3 | -6.267 | `N=C(N)NC(=O)c1nccnc1N` |
| 4 | -6.099 | `C[C@@H]1CN[C@H]2NC(N)=NC(=O)[C@@H]2N1` |
| 5 | -6.065 | `N=C(N)NC(=O)NC(=N)N` |

## Run (when Galaxy API is up)

```bash
python3 research/anti-virus/science_sprint/track_inh_ensemble_docking.py \
  --baseline-docking-json research/anti-virus/runs/publication_20260528T223525Z/zinc150_screen/vina/docking_autodock_vina_results.json \
  --top-n 5
```

After completion, reconcile:

```bash
python3 research/anti-virus/scripts/reconcile_ensemble_docking.py \
  research/anti-virus/science_sprint/runs/<TIMESTAMP>/track_inh_ensemble
```

**Expected:** honest negative on deposit-only ranking (prior ZINC150 top-5 ensemble: 0/5 improved vs rigid).
