# ANDV Inhibitor Manuscript — v1.1 addendum (ZINC150 + MM-GBSA)

**Base draft:** `MANUSCRIPT_ANDV_INHIBITOR_v1_0.md`  
**Campaign:** `publication_20260528T223525Z` + pipeline `andv_nf_pipeline_20260513T032000Z`  
**Date:** 2026-06-03

---

## Abstract supplement (replace final sentence in v1.0)

We extended the demonstration triad with a **145-compound ZINC20 screen** on PDB 9P3I (best rigid Vina **−6.267 kcal/mol**, INH-01). Explicit-solvent MD on the top hit (500k steps, CPU Batch) yielded stable protein backbone RMSD **0.41 nm**. MM-GBSA (gmx_MMPBSA v1.5, GB igb=2, 19 frames) gave **ΔG_bind −10.49 ± 0.46 kcal/mol** (Ki ≈ 20 nM), supporting further medchem review—not a clinical potency claim.

---

## Methods addendum

### ZINC150 ADMET + Vina screen

145 ligands from the publication ZINC20 mirror were docked to 9P3I with the institutional AutoDock Vina module (same pocket box as chained run `032000Z`). ADMET panels preceded docking. Artifacts: `zinc150_screen/vina/docking_autodock_vina_results.json`.

### GROMACS MD + MM-GBSA (INH-01)

Full 9P3I tetramer + INH-01 (`N=C(N)NC(=O)c1nccnc1N`) via `gromacs_protein_md` (run `28fd9a07`; S3 outdir `d64daac1`). Production: 500k steps × 2 fs (~1 ns). MM-GBSA standalone Batch job **`ffc49896`** on ECR `ambertools-gromacs-nf:1.2.0` with Protein/LIG index groups, frames 10–100, interval 5.

---

## Results addendum

### Table 3 — ZINC150 top hits (rigid Vina)

| ID | SMILES | Vina (kcal/mol) | MM-GBSA ΔG (kcal/mol) | Notes |
|----|--------|-----------------|------------------------|-------|
| INH-01 | `N=C(N)NC(=O)c1nccnc1N` | **−6.267** | **−10.49 ± 0.46** | MD + MM-GBSA complete |
| INH-02 | `CNC1=NC(N)=C2NCCN=C2N1` | −5.881 | pending | hERG flag |
| INH-03 | `Nc1oc2c(N)[n+]([O-])n(O)c2c1O` | −5.678 | pending | DILI flag |
| INH-04 | `O=C(O)[C@@H]1O[C@H](O)...` | −5.603 | pending | poor BBB |
| INH-05 | `C[C@]12NCCN3CCN(CCN1)[C@@H]32` | −5.599 | pending | — |

### MD stability (INH-01)

101-frame trajectory analysis: mean protein backbone RMSD **0.407 nm** (max 0.70 nm). Complex remained stable for MM-GBSA rescoring.

### MM-GBSA interpretation

ΔG_bind **−10.49 kcal/mol** classifies as a **strong binder** under campaign thresholds (< −10 kcal/mol). This is a scoring-function estimate on a single trajectory; experimental SPR or pseudotype entry assays are required before synthesis orders (see `wet_lab_package/INHIBITOR_COMPOUND_SHORTLIST.md`).

---

## Discussion addendum

The ZINC150 expansion moves beyond the three-compound demonstration library while preserving the same pocket geometry. INH-01 combines the best rigid Vina score with favorable MM-GBSA rescoring, whereas weaker Vina hits (INH-02–05) remain computational backups until MD/MM-GBSA completes. The generative module’s zero-retained outcome and the ensemble-docking gains on aspirin/paracetamol remain valid complementary findings from v1.0.

---

## Data availability (add)

| Artifact | Location |
|----------|----------|
| ZINC150 Vina JSON | `runs/publication_20260528T223525Z/zinc150_screen/vina/` |
| INH-01 MD + MM-GBSA | S3 `.../parallel-inhibitor-20260513T032000Z/d64daac1/` |
| binding_summary.json | `05_gromacs_mmgbsa_inh01/mmgbsa/` (local mirror) |
| MM-GBSA standalone script | `scripts/run_mmgbsa_standalone_batch.sh` |
