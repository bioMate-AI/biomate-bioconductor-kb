# BioMate Drug Development Workflow Pricing Table
# 133 workflows across 6 domains | Date: 2026-05-07

## Pricing Methodology

**Hardware tiers:**
| Tier | CPU | GPU | Notes |
|---|---|---|---|
| Economy | 2 vCPU / 4 GB Fargate Spot (~$0.030/hr eff.) | g4dn.xlarge T4 $0.526/hr | Spot ~70% discount; may interrupt |
| Balanced | 4 vCPU / 8 GB Fargate on-demand ($0.200/hr) | g4dn.2xlarge T4 $0.752/hr | Default recommended |
| Performance | 8 vCPU / 16 GB Fargate on-demand ($0.400/hr) | g5.4xlarge A10G $1.624/hr | Fastest; 2× GPU speed |

**Cost components:** Compute (Fargate/GPU) + S3 storage (30-day) + egress (1–3 downloads)
**Suggested price:** 2.5× total cost, minimum $0.10, rounded to clean price points
**Data sources:** ✅ Real AWS Batch measurement | 📐 Config spec + algorithm estimate

**Standard inputs used:**
- Compound workflows: 100 SMILES
- PK/PD workflows: 10 subjects × 12 timepoints
- MD simulations: 10ns, ~50K-atom system
- CryoEM SPA: 1,000 micrographs
- Cryo-ET: 30 tilt series

---

## Drug Discovery (51 workflows)

### CPU Workflows (43)

| Workflow | Steps | Max vCPU | Max RAM | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| ADMET_pred | 1 | 4 | 8 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.0m / **$0.10** | $0.000 | ✅ |
| adaptive_trial_design | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| alphafold_db_search | 1 | 1 | 2 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| apply_vcog_grade | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| assay_ingestion_and_ranking | 3 | 2 | 4 GB | 6.5m / **$0.10** | 6.3m / **$0.10** | 6.2m / **$0.10** | $0.000 | 📐 |
| bispecific_antibody_design | 2 | 4 | 8 GB | 6.7m / **$0.10** | 5.5m / **$0.10** | 4.8m / **$0.10** | $0.001 | 📐 |
| clinical_trial_simulation | 1 | 4 | 8 GB | 2.0m / **$0.10** | 2.0m / **$0.10** | 2.0m / **$0.10** | $0.000 | ✅ |
| covalent_warhead_design | 1 | 4 | 8 GB | 3.4m / **$0.10** | 2.8m / **$0.10** | 2.4m / **$0.10** | $0.000 | 📐 |
| cro_submission_export | 3 | 2 | 4 GB | 6.4m / **$0.10** | 6.2m / **$0.10** | 6.1m / **$0.10** | $0.000 | 📐 |
| cyp_ddi_panel | 5 | 4 | 8 GB | 13.4m / **$0.10** | 11.9m / **$0.10** | 11.0m / **$0.10** | $0.000 | 📐 |
| docking_autodock_vina | 3 | 8 | 16 GB | 9.4m / **$0.10** | 7.9m / **$0.10** | 7.0m / **$0.10** | $0.005 | 📐 |
| drug_moa_rnaseq | 2 | 8 | 32 GB | 9.4m / **$0.10** | 7.0m / **$0.10** | 5.5m / **$0.10** | $0.143 | 📐 |
| fcrn_antibody_pk | 4 | 2 | 4 GB | 4.2m / **$0.10** | 4.0m / **$0.10** | 3.8m / **$0.10** | $0.000 | ✅ |
| hts_plate_qc_hit_calling | 2 | 4 | 8 GB | 5.5m / **$0.10** | 4.8m / **$0.10** | 4.4m / **$0.10** | $0.002 | 📐 |
| ich_s5_reproductive_tox | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| ich_s7a_safety_pharmacology | 4 | 4 | 8 GB | 4.6m / **$0.10** | 4.4m / **$0.10** | 4.3m / **$0.10** | $0.000 | ✅ |
| ivive_hepatic_clearance | 2 | 2 | 4 GB | 4.5m / **$0.10** | 4.3m / **$0.10** | 4.2m / **$0.10** | $0.000 | 📐 |
| lnp_endosomal_escape | 1 | 4 | 8 GB | 3.4m / **$0.10** | 2.8m / **$0.10** | 2.4m / **$0.10** | $0.000 | 📐 |
| lnp_formulation_optimization | 1 | 4 | 8 GB | 3.8m / **$0.10** | 3.0m / **$0.10** | 2.5m / **$0.10** | $0.000 | 📐 |
| moe_covalent_docking | 1 | 8 | 32 GB | 5.6m / **$0.10** | 4.0m / **$0.10** | 3.0m / **$0.10** | $0.011 | 📐 |
| nca_pknca | 3 | 2 | 8 GB | 7.4m / **$0.10** | 6.8m / **$0.10** | 6.4m / **$0.10** | $0.001 | 📐 |
| nonmem_poppk | 3 | 8 | 16 GB | 22.2m / **$0.10** | 15.0m / **$0.10** | 10.5m / **$0.10** | $0.003 | 📐 |
| p0_docking_validation | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| p0_mrna_validation | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| p0_pharmacophore_validation | 1 | 2 | 4 GB | 2.1m / **$0.10** | 2.1m / **$0.10** | 2.0m / **$0.10** | $0.000 | 📐 |
| p0_pkpd_semaglutide | 1 | 2 | 4 GB | 2.1m / **$0.10** | 2.1m / **$0.10** | 2.0m / **$0.10** | $0.000 | 📐 |
| pbpk_pediatric | 4 | 4 | 8 GB | 4.8m / **$0.10** | 4.6m / **$0.10** | 4.5m / **$0.10** | $0.001 | ✅ |
| pbpk_simulation | 2 | 4 | 8 GB | 5.2m / **$0.10** | 4.7m / **$0.10** | 4.3m / **$0.10** | $0.001 | 📐 |
| pharmacophore_filtering | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| pk_sim_pbpk | 4 | 4 | 8 GB | 9.6m / **$0.10** | 8.9m / **$0.10** | 8.4m / **$0.10** | $0.001 | ✅ |
| pocket_detection_druggability | 1 | 4 | 8 GB | 3.4m / **$0.10** | 2.8m / **$0.10** | 2.4m / **$0.10** | $0.000 | 📐 |
| predict_admet_properties | 1 | 4 | 8 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.0m / **$0.10** | $0.000 | ✅ |
| proteome_selectivity_profiling | 1 | 4 | 16 GB | 3.8m / **$0.10** | 3.0m / **$0.10** | 2.5m / **$0.10** | $0.005 | 📐 |
| scaffold_hopping | 4 | 4 | 16 GB | 13.2m / **$0.10** | 10.9m / **$0.10** | 9.5m / **$0.10** | $0.000 | 📐 |
| schrodinger_glide_docking | 2 | 8 | 32 GB | 8.5m / **$0.10** | 6.5m / **$0.10** | 5.2m / **$0.10** | $0.057 | 📐 |
| simcyp_pbpk | 2 | 4 | 16 GB | 6.2m / **$0.10** | 5.2m / **$0.10** | 4.6m / **$0.10** | $0.001 | 📐 |
| sirna_offtarget_analysis | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| survival_analysis_km | 4 | 2 | 4 GB | 4.3m / **$0.10** | 4.1m / **$0.10** | 4.0m / **$0.10** | $0.000 | ✅ |
| syncraft_synthesizability | 1 | 4 | 8 GB | 3.8m / **$0.10** | 3.0m / **$0.10** | 2.5m / **$0.10** | $0.000 | 📐 |
| target_engagement_kinetics | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| target_tractability_scorer | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| transporter_ddi | 3 | 4 | 8 GB | 8.2m / **$0.10** | 7.2m / **$0.10** | 6.6m / **$0.10** | $0.000 | 📐 |
| transporter_ddi_pgp_bcrp | 3 | 4 | 8 GB | 8.2m / **$0.10** | 7.2m / **$0.10** | 6.6m / **$0.10** | $0.000 | 📐 |

### GPU / Hybrid Workflows (8)

| Workflow | Type | Steps | GPU | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| aizynthfinder_retrosynthesis | GPU | 1 | T4→A10G | 12.0m / **$0.10** | 12.0m / **$0.10** | 12.0m / **$0.50** | $0.002 | 📐 |
| amber_pmemd_md | Hybrid | 5 | T4→A10G | 233.4m / **$7.00** | 223.0m / **$9.00** | 216.5m / **$17.00** | $1.145 | 📐 |
| drugclip_virtual_screening | GPU | 1 | T4→A10G | 17.0m / **$0.10** | 17.0m / **$0.10** | 17.0m / **$1.00** | $0.002 | 📐 |
| gromacs_protein_md | Hybrid | 8 | T4→A10G | 290.1m / **$9.00** | 274.9m / **$12.00** | 265.5m / **$20.00** | $1.431 | ✅ CPU steps; 📐 GPU |
| openfe_rbfe | Hybrid | 5 | T4→A10G | 317.2m / **$8.00** | 314.0m / **$11.00** | 312.0m / **$20.00** | $0.572 | 📐 |
| reinvent4_lead_design | GPU | 1 | T4→A10G | 17.0m / **$0.10** | 17.0m / **$0.10** | 17.0m / **$1.00** | $0.005 | 📐 |
| scfv_antibody_design | GPU | 1 | T4→A10G | 22.0m / **$0.10** | 22.0m / **$0.50** | 22.0m / **$1.00** | $0.011 | 📐 |
| structure_prediction_docking | Hybrid | 3 | T4→A10G | 53.7m / **$1.00** | 52.5m / **$2.00** | 51.8m / **$4.00** | $0.286 | 📐 |

---

## Pharmacology (48 workflows)

### CPU Workflows (47)

| Workflow | Steps | Max vCPU | Max RAM | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| ADMET_pred | 1 | 4 | 8 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.0m / **$0.10** | $0.000 | ✅ |
| allometric_scaling | 1 | 2 | 4 GB | 2.3m / **$0.10** | 2.2m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| analyze_accelerated_stability_of_pharmaceutical_formulations | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| analyze_fda_safety_signals | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.002 | 📐 |
| analyze_interaction_mechanisms | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| analyze_radiolabeled_antibody_biodistribution | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| analyze_western_blot | 1 | 2 | 4 GB | 2.3m / **$0.10** | 2.2m / **$0.10** | 2.1m / **$0.10** | $0.001 | 📐 |
| analyze_xenograft_tumor_growth_inhibition | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| antibody_developability | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| apply_vcog_grade | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| bi_exp_model | 1 | 2 | 4 GB | 2.3m / **$0.10** | 2.2m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| biomarker_patient_enrichment | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| calculate_physicochemical_properties | 1 | 2 | 4 GB | 2.1m / **$0.10** | 2.1m / **$0.10** | 2.0m / **$0.10** | $0.000 | 📐 |
| check_drug_combination_safety | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| check_fda_drug_recalls | 1 | 2 | 4 GB | 2.3m / **$0.10** | 2.2m / **$0.10** | 2.1m / **$0.10** | $0.001 | 📐 |
| cns_penetration_prediction | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| dart_toxicity_prediction | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| docking_autodock_vina | 3 | 8 | 16 GB | 9.4m / **$0.10** | 7.9m / **$0.10** | 7.0m / **$0.10** | $0.005 | 📐 |
| estimate_alpha_particle_radiotherapy_dosimetry | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| exposure_response_modeling | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| exposure_response_modelling | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| find_alternative_drugs_ddinter | 1 | 2 | 4 GB | 2.3m / **$0.10** | 2.2m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| genotoxicity_ames_prediction | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| get_fda_drug_label_info | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| grade_adverse_events_using_vcog_ctcae | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| herg_cardiac_safety_qsar | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| ivive_hepatic_clearance | 2 | 2 | 4 GB | 4.5m / **$0.10** | 4.3m / **$0.10** | 4.2m / **$0.10** | $0.000 | 📐 |
| membrane_permeability_prediction | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| metabolite_prediction_biotransformer | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| nanoparticle_pk_biodistribution | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| nlmixr2_population_pk | 2 | 8 | 32 GB | 14.8m / **$0.10** | 10.0m / **$0.10** | 7.0m / **$0.10** | $0.003 | 📐 |
| oral_absorption_bcs_model | 1 | 2 | 4 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| pbpk_disease_state | 2 | 4 | 8 GB | 5.1m / **$0.10** | 4.6m / **$0.10** | 4.3m / **$0.10** | $0.001 | 📐 |
| pbpk_pediatric_pregnancy | 3 | 4 | 8 GB | 8.0m / **$0.10** | 7.1m / **$0.10** | 6.5m / **$0.10** | $0.001 | 📐 |
| perform_mwas_cyp2c19_metabolizer_status | 1 | 8 | 16 GB | 7.4m / **$0.10** | 5.0m / **$0.10** | 3.5m / **$0.10** | $0.002 | 📐 |
| pharmacogenomics_pgx_report | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| phase2_dose_justification | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| polymorph_stability_screening | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| predict_admet_properties | 1 | 4 | 8 GB | 2.2m / **$0.10** | 2.1m / **$0.10** | 2.0m / **$0.10** | $0.000 | ✅ |
| predict_binding_affinity_protein_1d_sequence | 1 | 4 | 8 GB | 3.8m / **$0.10** | 3.0m / **$0.10** | 2.5m / **$0.10** | $0.001 | 📐 |
| qsar_rf_model | 2 | 4 | 8 GB | 6.2m / **$0.10** | 5.2m / **$0.10** | 4.6m / **$0.10** | $0.001 | 📐 |
| repeated_dose_tox_prediction | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| retrieve_topk_repurposing_drugs_from_disease_txgnn | 1 | 4 | 8 GB | 3.8m / **$0.10** | 3.0m / **$0.10** | 2.5m / **$0.10** | $0.001 | 📐 |
| run_3d_chondrogenic_aggregate_assay | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| run_autosite | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.001 | 📐 |
| sigmoid | 1 | 2 | 4 GB | 2.1m / **$0.10** | 2.1m / **$0.10** | 2.0m / **$0.10** | $0.000 | 📐 |
| transporter_ddi_prediction | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |

### GPU / Hybrid Workflows (1)

| Workflow | Type | Steps | GPU | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| run_diffdock_with_smiles | GPU | 1 | T4→A10G | 12.0m / **$0.50** | 12.0m / **$0.50** | 12.0m / **$1.00** | $0.143 | 📐 |

---

## Cryo-EM (15 workflows)

### CPU Workflows (2)

| Workflow | Steps | Max vCPU | Max RAM | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| import_micrographs | 1 | 2 | 4 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.011 | 📐 |
| import_particles | 1 | 2 | 4 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.011 | 📐 |

### GPU / Hybrid Workflows (13)

| Workflow | Type | Steps | GPU | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| 3d_variability_analysis | GPU | 1 | T4→A10G | 32.0m / **$2.00** | 32.0m / **$2.50** | 32.0m / **$3.50** | $0.572 | 📐 |
| 3d_variability_pipeline | GPU | 1 | T4→A10G | 42.0m / **$3.00** | 42.0m / **$3.50** | 42.0m / **$5.00** | $0.858 | 📐 |
| cryosparc_standard_spa | Hybrid | 7 | T4→A10G | 151.7m / **$10.00** | 150.5m / **$11.00** | 149.8m / **$16.00** | $2.861 | 📐 |
| filament_tracer | GPU | 1 | T4→A10G | 12.0m / **$0.50** | 12.0m / **$0.50** | 12.0m / **$1.00** | $0.143 | 📐 |
| focused_refinement_pipeline | GPU | 1 | T4→A10G | 32.0m / **$2.00** | 32.0m / **$2.50** | 32.0m / **$3.50** | $0.572 | 📐 |
| global_ctf_refinement | GPU | 1 | T4→A10G | 22.0m / **$1.00** | 22.0m / **$1.00** | 22.0m / **$2.00** | $0.286 | 📐 |
| helical_refinement | GPU | 1 | T4→A10G | 32.0m / **$2.00** | 32.0m / **$2.50** | 32.0m / **$3.50** | $0.572 | 📐 |
| helical_spa_pipeline | Hybrid | 5 | T4→A10G | 87.7m / **$7.00** | 86.5m / **$8.00** | 85.8m / **$11.00** | $2.289 | 📐 |
| local_refinement | GPU | 1 | T4→A10G | 22.0m / **$1.00** | 22.0m / **$1.00** | 22.0m / **$2.00** | $0.286 | 📐 |
| particle_subtraction | GPU | 1 | T4→A10G | 12.0m / **$0.50** | 12.0m / **$0.50** | 12.0m / **$1.00** | $0.143 | 📐 |
| symmetry_expansion | GPU | 1 | T4→A10G | 12.0m / **$0.50** | 12.0m / **$0.50** | 12.0m / **$1.00** | $0.143 | 📐 |
| topaz_extract | GPU | 1 | T4→A10G | 17.0m / **$0.10** | 17.0m / **$0.50** | 17.0m / **$1.00** | $0.057 | 📐 |
| topaz_train | GPU | 1 | T4→A10G | 32.0m / **$0.50** | 32.0m / **$0.50** | 32.0m / **$2.00** | $0.005 | 📐 |

---

## Cryo-ET (5 workflows)

### CPU Workflows (1)

| Workflow | Steps | Max vCPU | Max RAM | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| import_tiltseries | 1 | 2 | 4 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.011 | 📐 |

### GPU / Hybrid Workflows (4)

| Workflow | Type | Steps | GPU | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| et_full_pipeline | Hybrid | 5 | T4→A10G | 110.9m / **$16.00** | 110.5m / **$17.00** | 110.2m / **$20.00** | $5.723 | 📐 |
| subtomogram_averaging | GPU | 1 | T4→A10G | 32.0m / **$8.00** | 32.0m / **$8.00** | 32.0m / **$9.00** | $2.861 | 📐 |
| tilt_alignment | GPU | 1 | T4→A10G | 22.0m / **$4.00** | 22.0m / **$4.00** | 22.0m / **$5.00** | $1.431 | 📐 |
| tomogram_reconstruction | GPU | 1 | T4→A10G | 42.0m / **$12.00** | 42.0m / **$12.00** | 42.0m / **$13.00** | $4.292 | 📐 |

---

## Structural Biology (2 workflows)

### GPU / Hybrid Workflows (2)

| Workflow | Type | Steps | GPU | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| boltz_structure_prediction | Hybrid | 2 | T4→A10G | 14.9m / **$0.10** | 14.5m / **$0.10** | 14.2m / **$0.50** | $0.057 | 📐 |
| chai1_structure_prediction | Hybrid | 2 | T4→A10G | 14.9m / **$0.10** | 14.5m / **$0.10** | 14.2m / **$0.50** | $0.057 | 📐 |

---

## Virtual Cell (12 workflows)

### CPU Workflows (9)

| Workflow | Steps | Max vCPU | Max RAM | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| cipa_cardiac_safety_ode | 1 | 4 | 8 GB | 2.5m / **$0.10** | 2.2m / **$0.10** | 2.1m / **$0.10** | $0.000 | 📐 |
| cpa_drug_combination_synergy | 1 | 4 | 8 GB | 5.6m / **$0.10** | 4.0m / **$0.10** | 3.0m / **$0.10** | $0.001 | 📐 |
| gears_perturbation_prediction | 1 | 4 | 8 GB | 7.4m / **$0.10** | 5.0m / **$0.10** | 3.5m / **$0.10** | $0.002 | 📐 |
| metabolic_flux_fba | 1 | 4 | 8 GB | 2.6m / **$0.10** | 2.3m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| ode_signaling_simulation | 1 | 4 | 8 GB | 2.9m / **$0.10** | 2.5m / **$0.10** | 2.2m / **$0.10** | $0.000 | 📐 |
| physicell_tumor_tgi | 1 | 8 | 16 GB | 11.0m / **$0.10** | 7.0m / **$0.10** | 4.5m / **$0.10** | $0.005 | 📐 |
| transcriptformer_cell_state | 1 | 4 | 8 GB | 9.2m / **$0.10** | 6.0m / **$0.10** | 4.0m / **$0.10** | $0.002 | 📐 |
| transcriptomic_moa_lincs | 1 | 4 | 8 GB | 3.8m / **$0.10** | 3.0m / **$0.10** | 2.5m / **$0.10** | $0.002 | 📐 |
| virtual_patient_cohort | 1 | 4 | 8 GB | 3.8m / **$0.10** | 3.0m / **$0.10** | 2.5m / **$0.10** | $0.001 | 📐 |

### GPU / Hybrid Workflows (3)

| Workflow | Type | Steps | GPU | Economy (wall/price) | Balanced (wall/price) | Performance (wall/price) | S3 | Source |
|---|---|---|---|---|---|---|---|---|
| cpa_synergy_gpu | GPU | 1 | T4→A10G | 12.0m / **$0.10** | 12.0m / **$0.10** | 12.0m / **$0.50** | $0.001 | 📐 |
| gears_perturbation_gpu | GPU | 1 | T4→A10G | 12.0m / **$0.10** | 12.0m / **$0.10** | 12.0m / **$0.50** | $0.002 | 📐 |
| transcriptformer_gpu | GPU | 1 | T4→A10G | 12.0m / **$0.10** | 12.0m / **$0.10** | 12.0m / **$0.50** | $0.002 | 📐 |

---

## Step-Level Detail — Measured Workflows

### gromacs_protein_md (10ns standard, real Batch data — 3 independent run replications)

| Step | Type | vCPU | RAM | Avg container time | Balanced cost | Source |
|---|---|---|---|---|---|---|
| LIGAND_PREP | CPU | 4 | 8 GB | 16.0s (±0.2s across 3 runs) | $0.000875 | ✅ Batch ×3 |
| SYSTEM_SETUP | CPU | 4 | 16 GB | 73.4s (±2.5s) | $0.004900 | ✅ Batch ×3 |
| ENERGY_MINIMIZATION | CPU | 8 | 16 GB | 195.6s (±9.6s) | $0.022508 | ✅ Batch ×3 |
| NVT_EQUILIBRATION | CPU | 16 | 32 GB | 268.6s (±2.9s) | $0.059420 | ✅ Batch ×3 |
| NPT_EQUILIBRATION | CPU | 16 | 32 GB | 147.0s (±1.7s) | $0.032540 | ✅ Batch ×3 |
| PRODUCTION_MD | GPU (T4) | 8+GPU | 32 GB | ~4h (10ns) estimated | $3.008 | 📐 GROMACS perf benchmark |
| TRAJECTORY_ANALYSIS | CPU | 8 | 16 GB | ~2 min | $0.010 | 📐 config |
| MM_GBSA | CPU | 8 | 32 GB | ~5 min | $0.022 | 📐 config |
| **TOTAL (10ns)** | | | | **~5.5h wall** | **~$3.16 compute + $1.47 S3** | |

**Key finding:** CPU prep steps are highly reproducible (CV < 5%). Total CPU prep = 700s / ~12 min.
PRODUCTION_MD estimated at ~4h for 10ns based on GROMACS benchmarks (T4 ≈ 50 ns/day for 50K-atom systems).
GPU run (profile: gpu_batch) submitted 2026-05-07 — await measurement.

---

### predict_admet_properties (100 SMILES, real Batch data)

| Step | vCPU | RAM | Real time | Real cost | Source |
|---|---|---|---|---|---|
| PREDICT_ADMET_PROPERTIES | 4 | 8 GB | 5.4s (16.8s container) | $0.000919 | ✅ Batch |

### clinical_trial_simulation (200 sims, real Batch data)

| Step | vCPU | RAM | Real time | Real cost | Source |
|---|---|---|---|---|---|
| BOIN_SIMULATION | 4 | 8 GB | 0.155s (11.9s container) | $0.000651 | ✅ Batch |

### pbpk_pediatric (real Batch data)

| Step | vCPU | RAM | Real time | Cost | Source |
|---|---|---|---|---|---|
| VALIDATE_COMPOUND_PARAMS | 4 | 8 GB | 15.2s | $0.000830 | ✅ Batch |
| PBPK_PEDIATRIC_SIMULATE | 4 | 8 GB | 17.2s | $0.000940 | ✅ Batch |
| EVALUATE_MATURATION | 4 | 8 GB | 17.9s | $0.000978 | ✅ Batch |
| GENERATE_FINAL_REPORT | 4 | 8 GB | 25.0s | $0.001366 | ✅ Batch |
| **TOTAL** | | | **75.3s / ~4 min wall** | **$0.004114** | |

### ich_s7a_safety_pharmacology (real Batch data)

| Step | vCPU | RAM | Real time | Cost | Source |
|---|---|---|---|---|---|
| VALIDATE_SAFETY_INPUTS | 1 | 1 GB | 16.3s | $0.000064 | ✅ Batch |
| ICH_S7A_ASSESS_CNS_RESP | 4 | 8 GB | 18.2s | $0.000994 | ✅ Batch |
| ICH_S7A_ASSESS_CV | 4 | 8 GB | 19.2s | $0.001049 | ✅ Batch |
| GENERATE_FINAL_REPORT | 2 | 4 GB | 20.5s | $0.000560 | ✅ Batch |
| **TOTAL** | | | **74.2s / ~4 min wall** | **$0.002667** | |

### fcrn_antibody_pk (real Batch data)

| Step | vCPU | RAM | Real time | Cost | Source |
|---|---|---|---|---|---|
| VALIDATE_ANTIBODY_PARAMS | 1 | 1 GB | 10.5s | $0.000041 | ✅ Batch |
| FCRN_PK_SIMULATION | 2 | 4 GB | 13.1s | $0.000358 | ✅ Batch |
| COMPARE_FC_MUTATIONS | 2 | 4 GB | 14.0s | $0.000382 | ✅ Batch |
| GENERATE_FINAL_REPORT | 2 | 4 GB | 17.6s | $0.000480 | ✅ Batch |
| **TOTAL** | | | **55.2s / ~4 min wall** | **$0.001261** | |

### survival_analysis_km (real Batch data)

| Step | vCPU | RAM | Real time | Cost | Source |
|---|---|---|---|---|---|
| VALIDATE_TRIAL_PARAMS | 1 | 1 GB | 10.8s | $0.000042 | ✅ Batch |
| SURVIVAL_ANALYSIS_KM | 2 | 4 GB | 13.1s | $0.000358 | ✅ Batch |
| EVALUATE_BOUNDARIES | 2 | 4 GB | 14.0s | $0.000382 | ✅ Batch |
| GENERATE_FINAL_REPORT | 2 | 4 GB | 17.6s | $0.000480 | ✅ Batch |
| **TOTAL** | | | **55.5s / ~4 min wall** | **$0.001262** | |

### run_diffdock_with_smiles (real Batch data — note: S3 staging fix needed)

| Step | vCPU | RAM | Real time | Cost | Source |
|---|---|---|---|---|---|
| RUN_DIFFDOCK_WITH_SMILES | 4 | 8 GB | 10.8s (container time) | $0.000591 | ✅ Batch |
| **Note** | | | | | S3 path staging bug: PDB not staged to container; actual docking not performed. Pricing estimate uses expected GPU time ~15 min. |

---

## Summary: Price Distribution (Balanced tier)

| Price band | Count | Example workflows |
|---|---|---|
| $0.10 (minimum) | 110 | ADMET_pred, adaptive_trial_design, aizynthfinder_retrosynthesis (+107 more) |
| $0.50 | 7 | scfv_antibody_design, run_diffdock_with_smiles, filament_tracer (+4 more) |
| $1.00 | 2 | global_ctf_refinement, local_refinement |
| $1.50–$5.00 | 6 | structure_prediction_docking, 3d_variability_analysis, 3d_variability_pipeline (+3 more) |
| $6–$20 | 8 | amber_pmemd_md, gromacs_protein_md, openfe_rbfe (+5 more) |

## Workflows Needing Real Batch Validation (Priority Queue)

These workflows have the highest revenue potential and should be validated first:

| Priority | Workflow | Domain | Type | Est. price | Reason |
|---|---|---|---|---|---|
| 1 | et_full_pipeline | cryo_et | Hybrid | $17.00 | High revenue |
| 2 | tomogram_reconstruction | cryo_et | GPU | $12.00 | High revenue |
| 3 | openfe_rbfe | drug_discovery | Hybrid | $11.00 | High revenue |
| 4 | cryosparc_standard_spa | cryo_em | Hybrid | $11.00 | High revenue |
| 5 | amber_pmemd_md | drug_discovery | Hybrid | $9.00 | GPU validation needed |
| 6 | subtomogram_averaging | cryo_et | GPU | $8.00 | GPU validation needed |
| 7 | helical_spa_pipeline | cryo_em | Hybrid | $8.00 | GPU validation needed |
| 8 | tilt_alignment | cryo_et | GPU | $4.00 | GPU validation needed |
| 9 | 3d_variability_pipeline | cryo_em | GPU | $3.50 | GPU validation needed |
| 10 | helical_refinement | cryo_em | GPU | $2.50 | GPU validation needed |
| 11 | focused_refinement_pipeline | cryo_em | GPU | $2.50 | GPU validation needed |
| 12 | 3d_variability_analysis | cryo_em | GPU | $2.50 | GPU validation needed |
| 13 | structure_prediction_docking | drug_discovery | Hybrid | $2.00 | GPU validation needed |
| 14 | local_refinement | cryo_em | GPU | $1.00 | GPU validation needed |
| 15 | global_ctf_refinement | cryo_em | GPU | $1.00 | GPU validation needed |
| 16 | topaz_train | cryo_em | GPU | $0.50 | GPU validation needed |
| 17 | topaz_extract | cryo_em | GPU | $0.50 | GPU validation needed |
| 18 | symmetry_expansion | cryo_em | GPU | $0.50 | GPU validation needed |
| 19 | scfv_antibody_design | drug_discovery | GPU | $0.50 | GPU validation needed |
| 20 | run_diffdock_with_smiles | pharmacology | GPU | $0.50 | GPU validation needed |