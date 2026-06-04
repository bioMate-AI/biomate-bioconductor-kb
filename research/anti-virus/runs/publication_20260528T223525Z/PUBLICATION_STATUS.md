# ANDV Publication Campaign — Run 20260528T223525Z

Real-data production run launched from `launch_andv_publication_campaign.py`.

> **2026-06-04 update:** ZINC600 **600/600** dock merged; Z600-R1 pose QC PASS (0.26 nm) — **INH-01** remains compute lead. `compute_package/` refreshed. Science gates in [`docs/ANDV_SCIENCE_COMPLETION_GATES.md`](../../../docs/ANDV_SCIENCE_COMPLETION_GATES.md).

> **2026-06-03 update:** Three-track status consolidated in [`docs/20260603_ANDV_THREE_TRACKS_STATUS_AND_PLAN.md`](../../../docs/20260603_ANDV_THREE_TRACKS_STATUS_AND_PLAN.md). Plan B wet-lab spec added; inhibitor manifest backfilled; Plan A figures regen from full GP multitool TSV.

> **2026-06-03 science bar:** Tracks are **not publication-ready on science grounds**. Author/deposit items deferred. See [`docs/ANDV_SCIENCE_COMPLETION_GATES.md`](../../../docs/ANDV_SCIENCE_COMPLETION_GATES.md) and [`docs/20260603_ANDV_PUBLICATION_READINESS_AND_BEST_SCIENCE.md`](../../../docs/20260603_ANDV_PUBLICATION_READINESS_AND_BEST_SCIENCE.md).

> **2026-06-03 update (INH-02–05):** Parallel MD+MM-GBSA complete for all ZINC150 top hits + aspirin control. Manifest backfilled; shortlist updated. See `INHIBITOR_COMPOUND_SHORTLIST.md`.

> **2026-06-03 update (MM-GBSA):** ECR v1.2.0 pushed; INH-01 **ΔG_bind = −10.49 ± 0.46 kcal/mol** (Ki ≈ 20 nM, job `ffc49896`). See [`mmgbsa_binding_summary_local.json`](mmgbsa_binding_summary_local.json).

> **2026-06-02 update:** GROMACS inh01 MD complete (CPU); HPC Batch queue repaired. See [`SESSION_20260602_GROMACS_HPC_INFRA.md`](SESSION_20260602_GROMACS_HPC_INFRA.md).

## Real inputs (not demo)

| Asset | Source | Size |
|-------|--------|------|
| ANDV GP protein | UniProt **Q9E006** (reviewed) | 1138 aa |
| ANDV GP CDS | Reverse-translated from Q9E006 (human codon table) | 3414 nt |
| HLA panel | A\*02:01, A\*01:01, A\*03:01, A\*24:02, B\*07:02, B\*08:01, B\*27:05, B\*35:01 | 8 alleles |
| Compound library | ZINC20 subset (local mirror) | 600 SMILES |
| Reference actives | Ribavirin, favipiravir, umifenovir, oseltamivir | 4 antivirals |
| Receptor | PDB **9P3I** (ANDV Gn/Gc tetramer) | S3 |

S3 prefix: `s3://biomate-nextflow-work/inputs/andv_campaign/publication_20260528/`

## Track status (2026-06-03)

| Track | Compute | Consolidated | Publication | Wet lab |
|-------|---------|--------------|-------------|---------|
| **Plan A** | Done | Yes | v1.2 + FigA0/A7 | **Tier A/B ranked** — `PLAN_A_SCIENCE_TIERS.md`; NetChop/TAP gap |
| **Plan B** | Done | Spec + FigC1/C2 | v1.2 supplement only | Not a vaccine product |
| **Inhibitor** | ZINC600 + MD + MM-GBSA | QC gates | v1.2 + FigB7/B8 | **Methods only** — MM-GBSA fail; **INH-01** lead (Vina −6.27, RMSD ~0.20 nm) |

## Plan A — completed

| Step | Status | Key metric |
|------|--------|------------|
| Full GP MHCnuggets | **Done** | 45,160 rows; **113 binders** |
| MHCflurry merge | **Done** | 604 unique binder peptides (multitool TSV) |
| **Dual consensus** | **Done** | **47** strict MHCnuggets+MHCflurry pairs (`PLAN_A_CONSENSUS_BINDERS.tsv`) |
| Plan A ↔ Plan B ORF map | **Done** | 65/65 wet-lab peptides encoded; 20 cytoplasmic/TM flagged |
| Cross-species conservation | **Done** | 54 conserved 9-mers; **18 overlap** with multitool binder 9-mers |
| Wet-lab package | **Done** | MB-01…15 + XSP-01…15 |

Artifacts: `plan_a_epitope/PLAN_A_FULL_GP_MULTITOOL.tsv`, `wet_lab_package/WET_LAB_CANDIDATES.md`

## Plan B — completed

| Step | Status | Key metric |
|------|--------|------------|
| Codon optimization | **Done** | **737 / 1138 codons (64.76%)** |
| RNA2D (5′ 500 nt) | **Done** | MFE **−182.7 kcal/mol** |
| LNP formulation | **Done** | EE 20%; endosomal escape 0.202 |
| P0 mRNA QC (ANDV) | **Done** | overall_pass: true |
| P0 spike (12819) | **Done** | overall_pass: true |
| NP-PK (12867) | **Done** | t½ 1.9 h; stealth POOR |

Artifacts: `plan_b_codon/`, `plan_b_lnp/`, `plan_b_p0/`, `plan_b_np_pk/`, **`plan_b_wet_lab/PLAN_B_WET_LAB_SPEC.md`**

## Inhibitor — publication campaign

| Step | Status | Key metric |
|------|--------|------------|
| ZINC600 Vina (full library) | **Done** | **600/600** docked; best **−6.527** (Z600-R1); INH-01 rank 3 **−6.267** |
| Z600-R1 pose QC | **Done** | Ligand RMSD **0.26 nm** PASS — not promoted vs INH-01 |
| Ensemble top-5 | **Done** | 1/5 improved vs rigid |
| GROMACS INH-01 MD | **Done** | RMSD ~0.41 nm (run `28fd9a07`) |
| GROMACS INH-02–05 + aspirin | **Done** | 500k-step CPU MD + MM-GBSA (runs `5e4afae3` … `e395d66c`) |
| MM-GBSA | **Done** | INH-01 −10.49; INH-02 −12.29; INH-03 −27.09; INH-04 −6.83; INH-05 −12.03; aspirin −13.05 kcal/mol |

Artifacts: `zinc150_screen/`, `05_gromacs_mmgbsa_inh01` … `inh05`, `05_gromacs_mmgbsa_aspirin`, `INHIBITOR_COMPOUND_SHORTLIST.md`

## Wet-lab quick links

- **Plan A peptides:** `wet_lab_package/WET_LAB_CANDIDATES.md`
- **Plan B mRNA/LNP:** `plan_b_wet_lab/PLAN_B_WET_LAB_SPEC.md`
- **Inhibitor compounds:** Track C in `wet_lab_package/` (post ZINC150 rebuild)

Re-assemble wet-lab package:

```bash
python3 research/anti-virus/scripts/assemble_wet_lab_candidates.py \
  --publication-run research/anti-virus/runs/publication_20260528T223525Z \
  --conservation-json research/anti-virus/runs/publication_20260528T223525Z/cross_species_conservation_full_gp.json \
  --epitope-tsv research/anti-virus/runs/publication_20260528T223525Z/plan_a_epitope/PLAN_A_FULL_GP_MULTITOOL.tsv \
  --docking-json research/anti-virus/runs/publication_20260528T223525Z/zinc150_screen/vina/docking_autodock_vina_results.json
```

Regenerate Plan A figures:

```bash
python3 research/anti-virus/scripts/generate_manuscript_plan_a_figures.py
```
