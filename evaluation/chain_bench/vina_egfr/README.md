# EGFR (PDB 1M17) hit-finding bench for `vina_virtual_screening_bench`

Scenario and chain design: `docs/20261101_VINA_SCREENING_CHAIN_BENCH_SCENARIO.md`. This directory holds the data
and the scorer, so a chain run can be checked against a known answer. Provenance and exact rules: `data/MANIFEST.json`.

## Data (`data/`)
| File | Content |
|---|---|
| `1M17.pdb` | RCSB entry, EGFR kinase domain + erlotinib (chain A, HET `AQ4 A 999`) |
| `erlotinib_crystal_ligand.pdb` | the 29 crystal heavy atoms of erlotinib (redocking reference) |
| `actives.smi` | 55 EGFR actives (BindingDB, IC50 <= 100 nM), incl. erlotinib, gefitinib, lapatinib, afatinib, osimertinib |
| `reference_actives.smi` | 5 of those 55, bare SMILES: input for `pharmacophore_filtering.reference_actives` |
| `decoys.smi` | 246 property-matched decoys (ZINC250k) |
| `library.smi` | **296 bare SMILES = 50 test actives + 246 decoys**, seeded shuffle: the `compound_library` input |
| `labels.csv` | `smiles,id,label,source`; label is `active`, `decoy` or `reference` (reference is excluded from scoring) |

Source deviation (see MANIFEST): the planned ChEMBL and DUD-E sources were unreachable on 2026-11-01 (ChEMBL REST
returned HTTP 500 on all endpoints including `/status`; DUD-E timed out), so actives come from BindingDB and decoys from
ZINC250k with the property-matching rule in the manifest. Ids are `BDBM...`, not CHEMBL ids. Decoys are not experimentally
confirmed non-binders. Rebuild: `python build_dataset.py <cache_dir>` (needs rdkit and network).

## Reference/test split (leakage control)
The pharmacophore step learns from `reference_actives`. If those same molecules were also scored, they would trivially
rank high. The 5 references (random, seeded, non-approved actives) are therefore **removed from `library.smi` and from
scoring**; the 50 remaining actives plus 246 decoys are the test set. The references come from diverse chemotypes, so the
pharmacophore built from them may be weak; if the filter step then drops many test actives, that is a real finding about
the pharmacophore step (the scorer counts such actives as unscored misses), not a harness fault. The 5 approved drugs
stay in the test set.

## Running on dev (needs user approval to sync first; nothing here runs on the laptop)
Chain inputs:
- `pocket_detection_druggability.pdb_input` = `data/1M17.pdb` (uploaded as a Galaxy dataset, or PDB id `1M17` if the workflow fetches by id)
- `pharmacophore_filtering.reference_actives` = `data/reference_actives.smi`
- `pharmacophore_filtering.compound_library` = `data/library.smi`
- docking: the receptor is the pocket step's PDB, `box_center`/`box_size` come from the pocket handoff; `smiles_list` from the filtered/ADMET output.

Positive control (separate small job): dock erlotinib (SMILES of `BDBM5446` in `labels.csv`) into 1M17 with
`reference_ligand` = `data/erlotinib_crystal_ligand.pdb`-derived SDF; the workflow's own `rmsd_vs_crystal_A` is
reported per ligand (main.nf:376-379, pass `<= 2.0` there; this bench uses `< 2.0`).

Important: only compounds that survive the pharmacophore/ADMET filters reach docking. Filtered-out test actives are
unscored and count as misses; this is intended (it measures the whole chain). To measure docking alone, feed `library.smi`
directly to `docking_autodock_vina`.

## Scoring
```
python score_run.py <docking_autodock_vina_results.json | scores.csv> [--labels data/labels.csv] \
    [--pose docking_poses/pose_000.pdbqt --rmsd-mode nearest] --out score_report
```
- Reads `results[]` from `docking_autodock_vina_results.json` (`docking_autodock_vina/main.nf` lines 366-374, 402-413,
  written at main.nf:417): fields `smiles` and `best_affinity_kcal_mol`; entries with `error` are unscored. Score sign:
  Vina kcal/mol, **more negative = better** (main.nf:431 comment), so the scorer ranks ascending.
- Outputs AUROC, EF1% and EF5% (top-N of the whole 296-compound library, N=ceil(frac*296); unscored ranked last),
  a 1000-permutation label-shuffle p-value for AUROC >= observed, and counts of unscored compounds / unscored actives.
- `redock_rmsd`: heavy-atom RMSD, no re-alignment (pose and crystal both in the receptor frame), symmetry-naive. Mode
  `ordered` pairs atoms by index; `nearest` pairs same-element atoms greedily by distance (use it when the pose atom order
  differs from the crystal file, which is the case for Vina output built from SMILES) and is optimistic. Pass: RMSD < 2.0 A.
- Matching library to docking rows is by exact SMILES, then RDKit canonical SMILES if rdkit is importable. If the chain
  rewrites SMILES without rdkit available, rows will not match and the scorer errors if none match.
- Tests: `python -m pytest test_score_run.py` (offline, synthetic scores).

## Cost / runtime
Not measured yet. Docking is per ligand (`Vina` with the workflow's `exhaustiveness`, one process, 296 ligands at most);
record the actual wall time and Batch cost from the first dev run here instead of estimating.
