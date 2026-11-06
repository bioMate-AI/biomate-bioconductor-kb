# Peptide Binding-Affinity Dataset v1 (the thin axis)

**Date:** 2026-10-04
**Collector:** `research/guangzhou_all_atom/collect_binding_affinity.py`
**Staged:** `s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/binding_affinity_v1/`

## Why
Pareto-DPO multi-objective peptide model already has permeability (CycPeptMPDB, 8466),
conformers, and structures. **Binding affinity (sequence/SMILES → Ki/Kd/IC50/EC50 vs a
protein target) was the missing axis.** The prior `collect_bindingdb.sh` scraped
`Download.jsp` for the TSV URL; that path is brittle. (The 202609 BindingDB subset did in
fact land on S3 — 50 MB / 171 k rows — but there was no ChEMBL pull, no structural peptide
gate, no unified labeled schema, and no PD-L1/αvβ6 flags.)

## What the new collector does
1. **ChEMBL (primary, stable REST API):** ChEMBL has **no `molecule_type=Peptide`**
   (cyclosporine is `Protein`, most synthetic peptides are `Small molecule`), so peptides
   are detected **structurally with RDKit** (≥2 α-residue backbones, or ≥3 amide bonds with
   MW ≥ 450). Anchored on `molecule_type=Protein` molecules carrying a canonical SMILES
   (MW ≤ 10 kDa) → 22,084 confirmed peptide molecules → their Ki/Kd/IC50/EC50 (nM)
   activities. **Also** pulls all affinity activities for the targets of interest and
   peptide-filters the ligands, so cyclic peptides classed `Small molecule` are not missed.
2. **BindingDB (secondary):** reuses the verified `BindingDB_All_202609` peptide subset on
   S3 (sha256 checked), or falls back to a **direct dated-zip download**
   (`BindingDB_All_YYYYmm_tsv.zip`, probing recent months) — never the JSP scrape. If no
   dated zip resolves it raises `BindingDB UNREACHABLE` rather than emitting a stub.
3. **Merge + dedup** on `(canonical_smiles|sequence, target_uniprot, affinity_type)`,
   median affinity kept, sources unioned. Every row passes the RDKit peptide gate.

## Schema
`id, sequence_or_smiles, smiles, sequence, target_uniprot, target_name, affinity_nM,
affinity_type, relation, source, cyclic_bool, is_pdl1, is_avb6, n_measurements`

## Results (verified real rows, not a stub)
| metric | value |
|---|---|
| total rows | **136,730** |
| peptide rows (all gated) | 136,730 |
| cyclic | 36,102 |
| unique targets (UniProt) | 2,702 |
| PD-L1 (CD274, Q9NZQ7) rows | 434 |
| αvβ6 (ITGAV P06756 / ITGB6 P18564) rows | 227 |
| ChEMBL-only / both / BindingDB-only | 16,861 / 11,168 / 108,701 |
| ChEMBL raw affinity rows | 40,347 |
| BindingDB raw affinity rows | 170,868 |

Targets of interest ChEMBL ids: PD-L1 `CHEMBL3580522` (+ PD-1/PD-L1 `CHEMBL4523993`,
CRBN/PD-L1 `CHEMBL5739543`); αvβ6 `CHEMBL2111416` (+ ITGAV `CHEMBL3660`, ITGB6 `CHEMBL4876`).

## Re-run
```bash
python3 collect_binding_affinity.py \
  --workdir /tmp/binding_work \
  --out data/raw/binding_affinity \
  --s3-stage s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/binding_affinity_v1/
```
Network results cache to `--workdir` (resumable); a bare re-run only redoes merge+dedup.

## Open items
- ChEMBL `Small molecule`-typed synthetic cyclic peptides are covered broadly only through
  BindingDB + the targeted-target pull; a full RDKit sweep of all 1.9 M small molecules was
  not done (cost). If more non-target cyclic-peptide coverage is needed, add a MW-bounded
  `Small molecule` activity pull with the same RDKit gate.
- Affinity relations (`<`/`>`/`~`) are retained per row but not censored-aware in the median.
