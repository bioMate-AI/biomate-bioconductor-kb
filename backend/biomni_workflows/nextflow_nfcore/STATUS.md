# Workflow Test Status

Last updated: 2026-01-27

## Summary
- **Total modules**: 237
- **Passed**: 165 (102 original + 63 fixed with proper test data)
- **Needs fixing**: 72

## Original 102 Passing (from commit 378d114a)

| Domain | Workflow |
|--------|----------|
| biochemistry | analyze_enzyme_kinetics_assay |
| biochemistry | analyze_itc_binding_thermodynamics |
| biochemistry | analyze_protein_conservation |
| biochemistry | dose_response |
| biochemistry | michaelis_menten |
| bioengineering | analyze_calcium_imaging_data |
| bioengineering | korsmeyer_peppas |
| bioengineering | perform_crispr_cas9_genome_editing |
| bioimaging | check_model_files_exist |
| bioimaging | command_iteration |
| bioimaging | create_affine_transform |
| bioimaging | create_deformable_transform |
| bioimaging | create_rigid_transform |
| bioimaging | load_image |
| bioimaging | patched_torch_load |
| bioimaging | register_images |
| bioimaging | save_image |
| bioimaging | setup_nnunet_environment |
| bioimaging | setup_registration_method |
| bioimaging | verify_nifti_input |
| biophysics | analyze_cell_morphology_and_cytoskeleton |
| biophysics | analyze_tissue_deformation_flow |
| biophysics | predict_protein_disorder_regions |
| cancer_biology | analyze_ddr_network_in_cancer |
| cancer_biology | perform_gene_expression_nmf_analysis |
| cell_biology | analyze_mitochondrial_morphology_and_potential |
| cell_biology | perform_facs_cell_sorting |
| database | get_genes_near_ccre |
| database | region_to_ccre_screen |
| genetics | bayesian_finemapping_with_deep_vi |
| genetics | identify_transcription_factor_binding_sites |
| genetics | liftover_coordinates |
| genetics | perform_pcr_and_gel_electrophoresis |
| genomics | analyze_chromatin_interactions |
| genomics | analyze_genomic_region_overlap |
| genomics | annotate_celltype_scRNA |
| genomics | check_ensembl_patterns |
| genomics | conda_env_exists |
| genomics | create_panhumanpy_env |
| genomics | custom_mode |
| genomics | get_gene_set_enrichment_analysis_supported_database_list |
| genomics | get_matrix |
| genomics | get_rna_seq_archs4 |
| genomics | get_uce_embeddings_scRNA |
| genomics | is_model_downloaded |
| glycoengineering | find_n_glycosylation_motifs |
| glycoengineering | list_glycoengineering_resources |
| glycoengineering | predict_o_glycosylation_hotspots |
| immunology | analyze_bacterial_growth_curve |
| immunology | analyze_cfse_cell_proliferation |
| immunology | analyze_cns_lesion_histology |
| immunology | analyze_immunohistochemistry_image |
| immunology | isolate_purify_immune_cells |
| immunology | track_immune_cells_under_flow |
| lab_automation | pick_first |
| lab_automation | run_async |
| lab_automation | target |
| lab_automation | test_pylabrobot_script |
| microbiology | annotate_bacterial_genome |
| microbiology | count_bacterial_colonies |
| microbiology | predict_rna_secondary_structure |
| microbiology | simulate_generalized_lotka_volterra_dynamics |
| molecular_biology | align_sequences |
| molecular_biology | annotate_open_reading_frames |
| molecular_biology | annotate_plasmid |
| molecular_biology | design_golden_gate_oligos |
| molecular_biology | design_primer |
| molecular_biology | digest_sequence |
| molecular_biology | find_restriction_enzymes |
| molecular_biology | find_sequence_mutations |
| molecular_biology | get_bacterial_transformation_protocol |
| molecular_biology | get_gene_coding_sequence |
| molecular_biology | get_oligo_annealing_protocol |
| molecular_biology | get_plasmid_sequence |
| molecular_biology | golden_gate_assembly |
| molecular_biology | pcr_simple |
| pathology | analyze_aortic_diameter_and_geometry |
| pathology | analyze_atp_luminescence_assay |
| pathology | analyze_bone_microct_morphometry |
| pathology | analyze_thrombus_histology |
| pathology | quantify_corneal_nerve_fibers |
| pathology | segment_and_quantify_cells_in_multiplexed_images |
| pharmacology | analyze_fda_safety_signals |
| pharmacology | analyze_interaction_mechanisms |
| pharmacology | analyze_xenograft_tumor_growth_inhibition |
| pharmacology | calculate_physicochemical_properties |
| pharmacology | check_drug_combination_safety |
| pharmacology | check_fda_drug_recalls |
| pharmacology | find_alternative_drugs_ddinter |
| pharmacology | get_fda_drug_label_info |
| pharmacology | grade_adverse_events_using_vcog_ctcae |
| pharmacology | perform_mwas_cyp2c19_metabolizer_status |
| pharmacology | run_diffdock_with_smiles |
| pharmacology | sigmoid |
| physiology | analyze_fatty_acid_composition_by_gc |
| physiology | cosinor_model |
| physiology | perform_cosinor_analysis |
| physiology | reconstruct_3d_face_from_mri |
| synthetic_biology | analyze_bacterial_growth_rate |
| synthetic_biology | engineer_bacterial_genome_for_therapeutic_delivery |
| synthetic_biology | identify_fas_functional_domains |
| systems_biology | hill_function |

## Fixed with Proper Default Test Data (63 workflows)

### None handling fixes (utility functions)

| Domain | Workflow | Fixed in |
|--------|----------|----------|
| biochemistry | analyze_circular_dichroism_spectra | a539980c |
| biochemistry | analyze_protease_kinetics | a539980c |
| biochemistry | analyze_rna_secondary_structure_features | a539980c |
| biochemistry | one_site_model | 9ff93590 |
| bioengineering | exp_decay | 9ff93590 |
| bioengineering | first_order | 9ff93590 |
| bioengineering | higuchi | 9ff93590 |
| bioengineering | zero_order | 9ff93590 |
| bioengineering | analyze_in_vitro_drug_release_kinetics | 3efbc2dd |
| bioengineering | default_whole_cell_model | 3efbc2dd |
| bioengineering | simulate_whole_cell_ode_model | 3efbc2dd |
| cancer_biology | norm_chr | 3fb78cd4 |
| database | reduce_tokens | 3fb78cd4 |
| genetics | elbo_loss | a88b8295 |
| genetics | forward | a88b8295 |
| immunology | logistic_growth | 9ff93590 |
| immunology | objective_function | 3fb78cd4 |
| immunology | simulate_cell_population | 3fb78cd4 |
| microbiology | bacterial_dynamics | 9ff93590 |
| microbiology | glv_equations | cdf190b7 |
| microbiology | methane_yield_model | cdf190b7 |
| microbiology | model_bacterial_growth_dynamics | 4fc77d11 |
| microbiology | vfa_production_model | cdf190b7 |
| molecular_biology | find_orfs_in_frame | 3fb78cd4 |
| molecular_biology | find_restriction_sites | 0d804e5d |
| molecular_biology | is_position_covered | 3fb78cd4 |
| molecular_biology | is_region_fully_covered | 3fb78cd4 |
| molecular_biology | merge_overlapping_regions | 0d804e5d |
| molecular_biology | reverse_complement | 9ff93590 |
| molecular_biology | search_gene | 4fc77d11 |
| pharmacology | bi_exp_model | 9ff93590 |
| physiology | mono_exp_model | 9ff93590 |
| physiology | pk_ode_system | cdf190b7 |
| physiology | analyze_ciliary_beat_frequency | (original) |
| synthetic_biology | gene_circuit_odes | 3fb78cd4 |
| synthetic_biology | gompertz_model | 9ff93590 |
| synthetic_biology | hamming_distance | 3fb78cd4 |
| systems_biology | dimerization_odes | a88b8295 |
| systems_biology | mass_action_kinetics | 9ff93590 |
| systems_biology | ode_system | a88b8295 |
| systems_biology | ras_ode_system | 3fb78cd4 |

### Fixed with JSON default parameters (actual test data)

| Domain | Workflow | Description |
|--------|----------|-------------|
| immunology | estimate_cell_cycle_phase_durations | Cell cycle phase estimation with flow cytometry data |
| immunology | analyze_ebv_antibody_titers | EBV ELISA antibody quantification |
| pharmacology | analyze_accelerated_stability_of_pharmaceutical_formulations | Pharmaceutical stability testing |
| pharmacology | estimate_alpha_particle_radiotherapy_dosimetry | Alpha-particle dosimetry calculation |
| physiology | analyze_hemodynamic_data | Blood pressure hemodynamic analysis |
| physiology | simulate_thyroid_hormone_pharmacokinetics | Thyroid hormone PK simulation |
| systems_biology | simulate_renin_angiotensin_system_dynamics | RAS dynamics simulation |
| systems_biology | model_protein_dimerization_network | Protein dimerization modeling |
| systems_biology | simulate_protein_signaling_network | Signaling network simulation |

## Workflows Requiring External Files

These workflows require external binary files (BAM, FCS, VCF, images) and need Docker container updates or test data files:

| Domain | Workflow | Required Input |
|--------|----------|----------------|
| cancer_biology | analyze_cell_senescence_and_apoptosis | FCS file |
| cancer_biology | analyze_copy_number_purity_ploidy_and_focal_events | BAM files |
| cancer_biology | detect_and_annotate_somatic_mutations | BAM files |
| cancer_biology | detect_and_characterize_structural_variations | BAM file |
| cell_biology | analyze_flow_cytometry_immunophenotyping | FCS file |
| cell_biology | quantify_cell_cycle_phases_from_microscopy | Image files |
| immunology | analyze_atac_seq_differential_accessibility | BAM files |
| immunology | analyze_cytokine_production_in_cd4_tcells | FCS files (FlowCytometryTools NumPy issue) |

## Workflows with Docker Dependency Issues

These workflows fail due to missing packages or library compatibility issues in the Docker container:

| Domain | Workflow | Issue |
|--------|----------|-------|
| pharmacology | predict_admet_properties | Missing descriptastorus, pandas-flavor |
| systems_biology | perform_flux_balance_analysis | Permission denied: /.cache |
| systems_biology | query_chatnt | Permission denied: /.cache |
| systems_biology | simulate_metabolic_network_perturbation | Permission denied: /.cache |

## Testing

Run `nextflow run subworkflows/{domain}/{workflow}/main.nf -profile docker` to test.
