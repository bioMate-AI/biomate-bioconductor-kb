# D2 (2ii) — HighFold/Boltz Augmentation: predicted bound cyclic complexes for 2c

**Status:** BUILD + REVIEW ONLY — no GPU launched. **Date:** 2026-09-30.
**Goal:** for cyclic peptides with a KNOWN protein target but NO experimental bound structure, PREDICT the bound
complex, so the 2c target-conditioned generator (M2c) gets more (peptide, receptor) training pairs than the ~235
experimental complexes the D2 mine yields. **TRAIN-ONLY, provenance-tagged, confidence-gated, never eval.**

## Pipeline (all three run on ONE spot GPU via `run_d2_augment_predict.sh`)

```
BindingDB peptide subset (S3)
   │  d2_augment_prep.py        (CPU; RDKit)
   ▼
jobs_canonical.jsonl  +  jobs_ncAA_defer.jsonl  +  jobs_bigrec_defer.jsonl
   │  d2_augment_predict.py     (GPU; Boltz `cyclic: true`; confidence gate iptm/plddt)
   ▼
predicted/<job>/complex.pdb + confidence.json   +   predictions_manifest.jsonl
   │  d2_augment_integrate.py   (CPU; PepGLAD converters)
   ▼
bound_cyclic_pred_v1/{index.txt, pdbs/<id>.pdb, bound_cyclic_manifest.jsonl}   ← PepGLAD format
   │  (feeds, unchanged)
   ▼
m2c_process_complexes.py  →  CoDesignDataset mmap  →  M2c target-SFT (train split only)
```

## Files
| File | Role |
|---|---|
| `d2_augment_prep.py` | BindingDB cyclic-peptide + UniProt-target pairs → predictor job list (RDKit backbone-walk sequence recovery; canonical-only, ncAA→defer) |
| `d2_augment_predict.py` | per job → Boltz YAML (`cyclic: true`) → `boltz predict` → confidence-gate (ipTM≥0.6, pLDDT≥0.7) |
| `d2_augment_integrate.py` | gate-passing complexes → PepGLAD `pdbs/`+`index.txt`+manifest (train-only, `<tool>_predicted`) |
| `run_d2_augment_predict.sh` | spot-GPU launcher (spot-only, dead-man's-switch, S3 stream, AZ fallback — mirrors `run_m2c_ldm_finetune.sh`) |

## Measured feasibility (on the real 171,006-row BindingDB peptide subset, 2026-09-30)
- **745 unique canonical (cyclic-peptide, target) jobs** across **155 unique targets** (≈3.2× the 235 experimental).
- **~thousands of ncAA (N-Me/D-AA) pairs** routed to `jobs_ncAA_defer.jsonl` (the HighFold-MeD / CyclicBoltz1 IP subset).
- Predictor: **Boltz-1/2** (MIT, pip-installable, auto-downloads open weights, native `cyclic: true`). HighFold3 is
  BLOCKED for unattended spot use (needs gated AlphaFold3 weights — see the review note).

## Run
```bash
# builds bundle, uploads, launches ONE spot GPU; produces the train-only predicted corpus on S3.
BINDINGDB_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/bindingdb_peptide/202609/bindingdb_peptide_subset.csv \
PRED_LIMIT=500 MIN_IPTM=0.6 MIN_PLDDT=0.7 \
bash run_d2_augment_predict.sh
```

## Discipline
- Every output row: `conformer_provenance="<tool>_predicted"`, `train_only=True`. `TRAIN_ONLY_DO_NOT_EVAL` sentinel +
  `train_only_ids.txt` written so the m2c split never places predicted complexes in val/test.
- Pairing is REAL (measured BindingDB binder + its UniProt target) — never fabricated.
- Predicted ≠ experimental: these inject predictor bias and are for volume/curriculum warm-up only, gated behind ipTM/pLDDT.
