# Structure-guided computational screening reveals conformational bottlenecks and rescoring limits in ANDV glycoprotein inhibitor design

**Manuscript version 1.2** (merged from v1.0 + v1.1 addendum)  
**Campaign:** `publication_20260528T223525Z` + pipeline `andv_nf_pipeline_20260513T032000Z`  
**Date:** 2026-06-03

---

## Authors

[Author A], [Author B], [Author C]  

[Institution], [City, Country]  

**Correspondence:** [email]

---

## Abstract

Andes virus (ANDV) causes hantavirus pulmonary syndrome with high case fatality, yet no approved small-molecule therapeutics exist. The viral surface glycoprotein (GP) mediates entry and is a rational target for structure-based design, but rigid-receptor docking has yielded weak predicted affinities, suggesting that conformational dynamics limit computational screening. Here we report a reproducible in silico funnel—pocket perception, pharmacophore filter, ADMET, AutoDock Vina, ensemble receptor sampling, explicit-solvent MD, and MM-GBSA—on PDB **9P3I**, executed on cloud infrastructure with archived chain-of-custody.

A six-compound demonstration library yielded three pharmacophore-filtered ligands with rigid Vina scores of −4.92 to −3.65 kcal/mol (aspirin strongest). Ensemble docking across six deposited conformers improved all three (aspirin −6.22 kcal/mol on 9P3Y; Δ −1.30 kcal/mol). A generative module completed with zero structures retained after filters. We extended screening to a **600-compound ZINC20 local mirror** (best rigid Vina **−6.527 kcal/mol**, Z600-R1; validated lead INH-01 **−6.267 kcal/mol**) and completed MD + MM-GBSA on the top five ZINC150 hits plus an aspirin control. INH-01 showed stable backbone RMSD (**0.41 nm**) and MM-GBSA **ΔG_bind −10.49 ± 0.46 kcal/mol**, but the **aspirin control scored −13.05 kcal/mol**, and INH-03 reached an implausible **−27.09 kcal/mol**—demonstrating that short MM-GBSA runs **do not reliably rank** chemotypes on this target without pose QC and biophysical validation.

We do not report cell antiviral potency. The contribution is a quantitative baseline, a tested ensemble workflow, and an honest assessment that rigid docking and current rescoring are insufficient for lead claims—experimental SPR or pseudotype assays on INH-01 are the appropriate next step.

---

## Introduction

Hantavirus pulmonary syndrome caused by Andes virus exemplifies zoonotic pathogens with limited therapeutic options. The envelope glycoprotein spike mediates attachment and fusion, making the ectodomain a focus for structure-guided small-molecule intervention. Recent cryo-EM structures (PDB 9P3I) enable modeling, but translating static coordinates into prioritized chemotypes requires disciplined cheminformatics with reproducible chain-of-custody between pharmacophore, ADMET, docking, and dynamics stages.

We implemented a sequential Nextflow ladder on BioMate/AWS Batch and report outcomes for (1) a pharmacophore-filtered demonstration triad, (2) ensemble docking across six receptor conformers, (3) a **600-compound ZINC20 mirror screen** (preceded by a 145-compound ADMET+Vina pilot), and (4) explicit-solvent MD with MM-GBSA on top Vina hits. Antiviral potency in cells is outside scope; readers should not extrapolate Vina or MM-GBSA estimates to clinical potency.

---

## Methods

### Structural model and chained pipeline (run `032000Z`)

Pocket detection on PDB **9P3I**; pharmacophore filter; ADMET; AutoDock Vina in a box anchored on the top pocket centroid; optional generative step (`06_reinvent4`; tool label `rdkit_brics_generation` in archived outputs). Property and docking stages consumed the pharmacophore-filtered SMILES list in the reference chained run.

### Ensemble docking (science sprint `20260527T195530Z`)

Six receptor conformers (fpocket fragment, 9P3I, 9P3Y, 9P3X, 9P3L, 9P3M); best Vina score per compound; improvement flagged at ≥0.5 kcal/mol vs rigid 9P3I baseline.

### ZINC150 ADMET + Vina

145 ligands from the publication ZINC20 mirror docked to 9P3I with the institutional Vina module (same pocket box as `032000Z`). Artifacts: `zinc150_screen/vina/docking_autodock_vina_results.json`.

### GROMACS MD + MM-GBSA (INH-01–05 + aspirin)

Full 9P3I tetramer + ligand via `gromacs_protein_md` (500k steps × 2 fs, CPU Batch). MM-GBSA via embedded Nextflow `MM_GBSA` on ECR `ambertools-gromacs-nf:1.2.0` (Protein/LIG index groups, frames 10–100, interval 5; GB igb=2). ~1 ns effective sampling per complex.

---

## Results

### Demonstration triad and ensemble

Rigid Vina: aspirin −4.92, paracetamol −4.64, phenol −3.65 kcal/mol. Ensemble bests: aspirin −6.22 (9P3Y), paracetamol −5.91, phenol −4.71 kcal/mol. Generative step: one molecule generated, **zero retained** after filters.

### ZINC600 screen

600 ligands docked; best rigid score **−6.527 kcal/mol** (Z600-R1, guanidine oligomer). INH-01 remains **−6.267 kcal/mol** with better pose QC (ligand RMSD **~0.20 nm** vs **~0.26 nm** for Z600-R1 after ~1 ns GROMACS). Top five from the pilot subset advanced to MD/MM-GBSA; rank-1 full-screen hit awaits medchem review before lead promotion.

### Table 3 — Vina + MM-GBSA panel

| ID | Vina (kcal/mol) | MM-GBSA ΔG_bind (kcal/mol) | RMSD mean (nm) | Expert read |
|----|-----------------|----------------------------|----------------|-------------|
| INH-01 | **−6.267** | **−10.49 ± 0.46** | 0.41 | Coherent — primary SPR candidate |
| INH-02 | −5.881 | −12.29 | — | hERG flag; pose QC required |
| INH-03 | −5.678 | **−27.09 ± 0.72** | 0.66 | Likely artifact |
| INH-04 | −5.603 | −6.83 | — | Weak — deprioritize |
| INH-05 | −5.599 | −12.03 | — | Backup after pose QC |
| Aspirin | ~−6.22 (ensemble) | **−13.05** | — | **Control failure** |

**Interpretation:** When the negative control outscores the proposed lead, MM-GBSA ranking is **not diagnostic** for prioritization without ligand RMSD plots, protonation review, and longer sampling. **Do not claim nM potency or a lead series** from this table alone.

### MD stability

INH-01 mean protein backbone RMSD **0.407 nm** over 101 frames supports a plausible initial complex; ~1 ns is insufficient for long-term stability claims.

---

## Discussion

The central intellectual contribution is that **rigid-receptor docking underestimates affinity** for this conformationally plastic GP assembly (ensemble Δ ~1.3 kcal/mol on the demo triad). The ZINC150 expansion shows modest rigid improvements (−6.3 kcal/mol best) consistent with weak in silico hits, not validated antivirals.

The MM-GBSA panel exposes **scoring and sampling limits**: aspirin and INH-03 anomalies indicate miscalibrated rescoring or incorrect poses. INH-01 remains the only compound warranting **SPR or thermal shift** before synthesis; INH-04 is a coherent weak negative; INH-02/03/05 require pose figures before backup prioritization.

Generative zero-retained outcome and pharmacophore-chain audit history (`20260512T181054Z`) reinforce that pipeline transparency matters as much as headline scores.

---

## Conclusions

We integrated pocket detection through MM-GBSA on an ANDV GP structural model with reproducible manifests. Ensemble docking improves demo scores; ZINC150 identifies INH-01 as the best combined Vina + MD candidate. MM-GBSA does **not** validate a lead series until control failures are resolved. The defensible narrative is a **computational triage funnel** with mandatory biophysical follow-up—not drug discovery success.

---

## Figures

Regenerate: `python3 research/anti-virus/scripts/generate_manuscript_inhibitor_figures.py`

| Figure | Description |
|--------|-------------|
| Fig B1–B6 | Pocket, funnel, demo docking, generative, 2D ligands, ensemble (v1.0 set) |
| **Fig B7** | ZINC150 Vina vs MM-GBSA panel — aspirin control failure |
| **Fig B8** | Pose QC — protein backbone RMSD vs MM-GBSA per hit |

---

## Data availability

| Artifact | Location |
|----------|----------|
| Chained run | `runs/andv_nf_pipeline_20260513T032000Z/` |
| ZINC150 Vina | `runs/publication_20260528T223525Z/zinc150_screen/vina/` |
| MD + MM-GBSA mirrors | `05_gromacs_mmgbsa_inh01` … `inh05`, `05_gromacs_mmgbsa_aspirin` |
| Wet-lab shortlist | `wet_lab_package/INHIBITOR_COMPOUND_SHORTLIST.md` |
| Audit (non-primary) | `runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md` |

---

## References

1. Trott O, Olson AJ. AutoDock Vina. *J Comput Chem*. 2010;31(2):455–461.  
2. Di Tommaso P, et al. Nextflow. *Nat Biotechnol*. 2017;35(4):316–319.  
3. [Insert Guo et al. ANDV GP structure; PDB 9P3I.]  
4. [Insert gmx_MMPBSA / AMBER GB citation.]  
5. [Insert ADMET tool references.]

**Supersedes:** `MANUSCRIPT_ANDV_INHIBITOR_v1_0.md`, `MANUSCRIPT_ANDV_INHIBITOR_v1_1.md`
