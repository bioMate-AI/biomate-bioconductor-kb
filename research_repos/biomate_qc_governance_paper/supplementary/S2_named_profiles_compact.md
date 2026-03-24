# Supplementary Table S2 — Named QC Profile Inventory (Compact)
**Paper:** BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale
**Source:** `QC_NAMED_PROFILES` constant, `backend/lib/galaxy/jobs/qc_trace_monitor.py` (line 69)
**Total profiles: 34**
**API endpoint:** `GET /api/qc/profiles`

For full profile descriptions, rationale, and complete reference lists see `supplementary/named_profiles_full.md`.

---

## RNA-seq (5 profiles)

| Profile ID | Key overrides vs. default | Primary reference |
|---|---|---|
| `rnaseq_polya_standard` | (none — platform defaults) | nf-core/rnaseq v3.14 |
| `rnaseq_ribodepleted` | `alignment_rate` 70→50%; `reads_surviving_pct` 70→65%; `assigned_reads_pct` 50→40% | Zhao S et al. 2020 RNA Biol 17(8):1105 |
| `rnaseq_ffpe` | `alignment_rate` 70→45%; `reads_surviving_pct` 70→60%; `q30_pct` 75→65% | Sinicropi D et al. 2012 PLoS ONE 7(5):e38396 |
| `rnaseq_single_nucleus` | `alignment_rate` 70→50% | 10x Genomics snRNA-seq Guide v2.0 (2023) |
| `rnaseq_nonmodel_organism` | `alignment_rate` 70→40%; `assigned_reads_pct` 50→30% | [BRONZE] community practice |

## DNA-seq / WGS / WES (6 profiles)

| Profile ID | Key overrides vs. default | Primary reference |
|---|---|---|
| `wgs_germline_standard` | (none — platform defaults) | GATK Best Practices Germline (2023) |
| `wgs_germline_lowpass` | `mean_coverage` 30→4×; `duplicate_pct` 40→60% | Rubinacci S et al. 2021 Nat Genet 53:120 |
| `wgs_somatic_tumor_only` | `mean_coverage` 30→80×; `duplicate_pct` 40→50% | GATK Mutect2 Best Practices (2023) |
| `wgs_ffpe` | `mean_coverage` (unchanged 30×); `duplicate_pct` 40→65% | Robbe P et al. 2018 Nat Med 24:1555 |
| `wes_research` | `mean_coverage` 30→50× | nf-core/sarek v3 WES defaults |
| `wes_clinical_germline` | `mean_coverage` 30→80×; `duplicate_pct` 40→30% | ACMG/AMP 2016 Standards for NGS |

## Single-cell RNA-seq (4 profiles)

| Profile ID | Key overrides vs. default | Primary reference |
|---|---|---|
| `scrna_standard` | (none — platform defaults) | 10x Genomics Cell Ranger v7 defaults |
| `scrna_cardiac` | `mito_fraction_pct` 20→40%; `mito_fraction_pct_warning` set at 25% | Simonson B et al. 2023 Circ Res; Kuppe C et al. 2022 Nature |
| `scrna_neuronal` | `mito_fraction_pct` 20→30%; `median_genes_per_cell` 500→300 | Allen Brain Atlas; Bakken TE et al. 2021 Nature 598:86 |
| `scrna_perturbation` | Adds: `guide_library_coverage_pct` ≥70%; `transfection_efficiency_pct` ≥30%; `max_doublet_fraction_pct` ≤10% | Replogle JM et al. 2022 Cell 185(14):2559 |

## Metagenomics (4 profiles)

| Profile ID | `classified_pct_critical` | `classified_pct_warning` | Primary reference |
|---|---|---|---|
| `metagenomics_human_gut` | 50% | 60% | HMP Consortium 2012 Nature 486:207 |
| `metagenomics_soil` | 3% | 8% | Bahram M et al. 2018 Nature 560:233; Delgado-Baquerizo M et al. 2018 Science 359:320 |
| `metagenomics_marine` | 4% | 10% | Sunagawa S et al. 2015 Science 348:1261359 |
| `metagenomics_clinical_pathogen` | 60% | 70% | [BRONZE] IDSA clinical metagenomics guidance (2024) |

## Cryo-EM (6 profiles)

| Profile ID | Key overrides vs. default | Primary reference |
|---|---|---|
| `cryoem_spa_purified` | (none — platform defaults) | EMPIAR deposition standards; EMDB validation (2024) |
| `cryoem_spa_standard` | Alias for `cryoem_spa_purified` — semantic tag with no threshold overrides | — |
| `cryoem_spa_membrane` | `total_drift_angstrom` 50→80 Å; `fit_quality` 0.70→0.65 | [BRONZE] Membrane protein cryo-EM community practice |
| `cryoem_spa_phase_plate` | `fit_quality` 0.70→0.65; VPP advisory thresholds activated (0.20–1.50 rad) | Danev & Bharat 2018 Trends Cell Biol |
| `cryoem_spa_lowdose` | `total_drift_angstrom` 50→60 Å; `fit_quality` 0.70→0.65 (low-dose SNR reduction) | [BRONZE] Rohou & Grigorieff 2015 J Struct Biol 192:216 |
| `cryoem_tomo_in_situ` | `total_drift_angstrom` 50→150 Å; `fit_quality` 0.70→0.50 (red-line floor); `correlation_score` 0.50→0.30 | [BRONZE] FIB-SEM cryo-ET community practice |

## Proteomics LC-MS/MS (4 profiles)

| Profile ID | Key overrides vs. default | Primary reference |
|---|---|---|
| `proteomics_standard` | (none — platform defaults) | [GOLD] Elias & Gygi 2007 Nat Methods; [SILVER] EuBIC 2018 |
| `proteomics_phospho` | `psm_count` 1000→500; `missed_cleavage_pct` 20→30%; `cv_pct` 20→25% | Beausoleil SA et al. 2006 Nat Biotechnol |
| `proteomics_plasma_biomarker` | `cv_pct` 20→15%; adds `missing_value_pct` ≤30% gate | Geyer PE et al. 2017 Cell Syst |
| `proteomics_chemoproteomics` | `psm_count` 1000→200 | [SILVER] ABPP community practice — enrichment ratio >3× |

## Cheminformatics (3 profiles)

| Profile ID | Key overrides vs. default | Primary reference |
|---|---|---|
| `compound_druglike` | `compound_mw_limit` 900→500 Da; `logp_limit` ≤5; `hbd_limit` ≤5; `hba_limit` ≤10 | [GOLD] Lipinski et al. 2001 Adv Drug Deliv Rev |
| `compound_natural_product` | `compound_mw_limit` 900→1000 Da; `logp_limit` removed | Newman & Cragg 2020 J Nat Prod |
| `compound_peptidomimetic` | `hbd_limit` 5→10; `hba_limit` 10→15 | Giordanetto & Kihlberg 2014 J Med Chem |

## Pharmacogenomics (2 profiles)

| Profile ID | `pgx_min_coverage` | Primary reference |
|---|---|---|
| `pgx_clinical` | 30× per PGx gene | [GOLD] CPIC guidelines (cpicpgx.org) |
| `pgx_research` | 15× per PGx gene | [SILVER] CPIC tier 2 research use |

---

## Evidence tier key

| Tier | Meaning |
|---|---|
| [GOLD] | Mandated by ENCODE4, GATK Best Practices, ACMG, or equivalent authoritative body. Cannot be overridden via `qc_overrides`. |
| [SILVER] | Supported by major bioinformatics pipelines or published national consortium guidelines. User-overridable with audit trail. |
| [BRONZE] | Community heuristic without formal publication. User-overridable. |
