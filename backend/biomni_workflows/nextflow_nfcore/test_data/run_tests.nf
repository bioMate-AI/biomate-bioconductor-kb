#!/usr/bin/env nextflow
/*
 * Test workflow for Biomni tools
 * Generated from Galaxy wrappers
 */

nextflow.enable.dsl = 2

// Module includes
include { DOSE_RESPONSE } from '../subworkflows/biochemistry/dose_response/main'
include { ANALYZE_PROTEIN_CONSERVATION } from '../subworkflows/biochemistry/analyze_protein_conservation/main'
include { ANALYZE_CIRCULAR_DICHROISM_SPECTRA } from '../subworkflows/biochemistry/analyze_circular_dichroism_spectra/main'
include { MICHAELIS_MENTEN } from '../subworkflows/biochemistry/michaelis_menten/main'
include { ANALYZE_ITC_BINDING_THERMODYNAMICS } from '../subworkflows/biochemistry/analyze_itc_binding_thermodynamics/main'
include { ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES } from '../subworkflows/biochemistry/analyze_rna_secondary_structure_features/main'
include { ONE_SITE_MODEL } from '../subworkflows/biochemistry/one_site_model/main'
include { ANALYZE_PROTEASE_KINETICS } from '../subworkflows/biochemistry/analyze_protease_kinetics/main'
include { ANALYZE_ENZYME_KINETICS_ASSAY } from '../subworkflows/biochemistry/analyze_enzyme_kinetics_assay/main'
include { ZERO_ORDER } from '../subworkflows/bioengineering/zero_order/main'
include { FIRST_ORDER } from '../subworkflows/bioengineering/first_order/main'
include { KORSMEYER_PEPPAS } from '../subworkflows/bioengineering/korsmeyer_peppas/main'
include { PERFORM_CRISPR_CAS9_GENOME_EDITING } from '../subworkflows/bioengineering/perform_crispr_cas9_genome_editing/main'
include { DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES } from '../subworkflows/bioengineering/decode_behavior_from_neural_trajectories/main'
include { SIMULATE_WHOLE_CELL_ODE_MODEL } from '../subworkflows/bioengineering/simulate_whole_cell_ode_model/main'
include { DEFAULT_WHOLE_CELL_MODEL } from '../subworkflows/bioengineering/default_whole_cell_model/main'
include { ANALYZE_CALCIUM_IMAGING_DATA } from '../subworkflows/bioengineering/analyze_calcium_imaging_data/main'
include { ANALYZE_CELL_MIGRATION_METRICS } from '../subworkflows/bioengineering/analyze_cell_migration_metrics/main'
include { HIGUCHI } from '../subworkflows/bioengineering/higuchi/main'
include { ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS } from '../subworkflows/bioengineering/analyze_in_vitro_drug_release_kinetics/main'
include { EXP_DECAY } from '../subworkflows/bioengineering/exp_decay/main'
include { ANALYZE_MYOFIBER_MORPHOLOGY } from '../subworkflows/bioengineering/analyze_myofiber_morphology/main'
include { CALCULATE_SIMILARITY_METRICS } from '../subworkflows/bioimaging/calculate_similarity_metrics/main'
include { PATCHED_TORCH_LOAD } from '../subworkflows/bioimaging/patched_torch_load/main'
include { CHECK_MODEL_FILES_EXIST } from '../subworkflows/bioimaging/check_model_files_exist/main'
include { QUICK_RIGID_REGISTRATION } from '../subworkflows/bioimaging/quick_rigid_registration/main'
include { SEGMENT_WITH_NN_UNET } from '../subworkflows/bioimaging/segment_with_nn_unet/main'
include { SAVE_IMAGE } from '../subworkflows/bioimaging/save_image/main'
include { SPLIT_MODALITIES } from '../subworkflows/bioimaging/split_modalities/main'
include { PREPARE_INPUT_FOR_NNUNET } from '../subworkflows/bioimaging/prepare_input_for_nnunet/main'
include { PREPROCESS_IMAGE } from '../subworkflows/bioimaging/preprocess_image/main'
include { QUICK_DEFORMABLE_REGISTRATION } from '../subworkflows/bioimaging/quick_deformable_registration/main'
include { CREATE_DEFORMABLE_TRANSFORM } from '../subworkflows/bioimaging/create_deformable_transform/main'
include { BATCH_REGISTER_IMAGES } from '../subworkflows/bioimaging/batch_register_images/main'
include { VERIFY_NIFTI_INPUT } from '../subworkflows/bioimaging/verify_nifti_input/main'
include { SETUP_NNUNET_ENVIRONMENT } from '../subworkflows/bioimaging/setup_nnunet_environment/main'
include { REGISTER_IMAGES } from '../subworkflows/bioimaging/register_images/main'
include { CREATE_RIGID_TRANSFORM } from '../subworkflows/bioimaging/create_rigid_transform/main'
include { COMMAND_ITERATION } from '../subworkflows/bioimaging/command_iteration/main'
include { SETUP_REGISTRATION_METHOD } from '../subworkflows/bioimaging/setup_registration_method/main'
include { CREATE_SEGMENTATION_VISUALIZATION } from '../subworkflows/bioimaging/create_segmentation_visualization/main'
include { LOAD_IMAGE } from '../subworkflows/bioimaging/load_image/main'
include { QUICK_AFFINE_REGISTRATION } from '../subworkflows/bioimaging/quick_affine_registration/main'
include { CREATE_AFFINE_TRANSFORM } from '../subworkflows/bioimaging/create_affine_transform/main'
include { ANALYZE_TISSUE_DEFORMATION_FLOW } from '../subworkflows/biophysics/analyze_tissue_deformation_flow/main'
include { PREDICT_PROTEIN_DISORDER_REGIONS } from '../subworkflows/biophysics/predict_protein_disorder_regions/main'
include { ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON } from '../subworkflows/biophysics/analyze_cell_morphology_and_cytoskeleton/main'
include { ANALYZE_DDR_NETWORK_IN_CANCER } from '../subworkflows/cancer_biology/analyze_ddr_network_in_cancer/main'
include { DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS } from '../subworkflows/cancer_biology/detect_and_annotate_somatic_mutations/main'
include { ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS } from '../subworkflows/cancer_biology/analyze_cell_senescence_and_apoptosis/main'
include { NORM_CHR } from '../subworkflows/cancer_biology/norm_chr/main'
include { DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS } from '../subworkflows/cancer_biology/detect_and_characterize_structural_variations/main'
include { ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS } from '../subworkflows/cancer_biology/analyze_copy_number_purity_ploidy_and_focal_events/main'
include { PERFORM_GENE_EXPRESSION_NMF_ANALYSIS } from '../subworkflows/cancer_biology/perform_gene_expression_nmf_analysis/main'
include { ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL } from '../subworkflows/cell_biology/analyze_mitochondrial_morphology_and_potential/main'
include { ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING } from '../subworkflows/cell_biology/analyze_flow_cytometry_immunophenotyping/main'
include { QUANTIFY_AND_CLUSTER_CELL_MOTILITY } from '../subworkflows/cell_biology/quantify_and_cluster_cell_motility/main'
include { QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY } from '../subworkflows/cell_biology/quantify_cell_cycle_phases_from_microscopy/main'
include { PERFORM_FACS_CELL_SORTING } from '../subworkflows/cell_biology/perform_facs_cell_sorting/main'
include { REDUCE_TOKENS } from '../subworkflows/database/reduce_tokens/main'
include { GET_HPO_NAMES } from '../subworkflows/database/get_hpo_names/main'
include { REGION_TO_CCRE_SCREEN } from '../subworkflows/database/region_to_ccre_screen/main'
include { BLAST_SEQUENCE } from '../subworkflows/database/blast_sequence/main'
include { GET_GENES_NEAR_CCRE } from '../subworkflows/database/get_genes_near_ccre/main'
include { LIFTOVER_COORDINATES } from '../subworkflows/genetics/liftover_coordinates/main'
include { ANALYZE_PROTEIN_PHYLOGENY } from '../subworkflows/genetics/analyze_protein_phylogeny/main'
include { ANALYZE_CAS9_MUTATION_OUTCOMES } from '../subworkflows/genetics/analyze_cas9_mutation_outcomes/main'
include { ANALYZE_CRISPR_GENOME_EDITING } from '../subworkflows/genetics/analyze_crispr_genome_editing/main'
include { IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES } from '../subworkflows/genetics/identify_transcription_factor_binding_sites/main'
include { FORWARD } from '../subworkflows/genetics/forward/main'
include { BAYESIAN_FINEMAPPING_WITH_DEEP_VI } from '../subworkflows/genetics/bayesian_finemapping_with_deep_vi/main'
include { FIT_GENOMIC_PREDICTION_MODEL } from '../subworkflows/genetics/fit_genomic_prediction_model/main'
include { ELBO_LOSS } from '../subworkflows/genetics/elbo_loss/main'
include { PERFORM_PCR_AND_GEL_ELECTROPHORESIS } from '../subworkflows/genetics/perform_pcr_and_gel_electrophoresis/main'
include { SIMULATE_DEMOGRAPHIC_HISTORY } from '../subworkflows/genetics/simulate_demographic_history/main'
include { UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS } from '../subworkflows/genomics/unsupervised_celltype_transfer_between_scRNA_datasets/main'
include { ANNOTATE_CELLTYPE_SCRNA } from '../subworkflows/genomics/annotate_celltype_scRNA/main'
include { CREATE_HARMONY_EMBEDDINGS_SCRNA } from '../subworkflows/genomics/create_harmony_embeddings_scRNA/main'
include { CREATE_PANHUMANPY_ENV } from '../subworkflows/genomics/create_panhumanpy_env/main'
include { GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST } from '../subworkflows/genomics/get_gene_set_enrichment_analysis_supported_database_list/main'
include { ANALYZE_GENOMIC_REGION_OVERLAP } from '../subworkflows/genomics/analyze_genomic_region_overlap/main'
include { INTERSPECIES_GENE_CONVERSION } from '../subworkflows/genomics/interspecies_gene_conversion/main'
include { GET_UCE_EMBEDDINGS_SCRNA } from '../subworkflows/genomics/get_uce_embeddings_scRNA/main'
include { PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2 } from '../subworkflows/genomics/perform_chipseq_peak_calling_with_macs2/main'
include { IS_MODEL_DOWNLOADED } from '../subworkflows/genomics/is_model_downloaded/main'
include { GENE_SET_ENRICHMENT_ANALYSIS } from '../subworkflows/genomics/gene_set_enrichment_analysis/main'
include { FIND_ENRICHED_MOTIFS_WITH_HOMER } from '../subworkflows/genomics/find_enriched_motifs_with_homer/main'
include { GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS } from '../subworkflows/genomics/generate_gene_embeddings_with_ESM_models/main'
include { ANNOTATE_CELLTYPE_WITH_PANHUMANPY } from '../subworkflows/genomics/annotate_celltype_with_panhumanpy/main'
include { CHECK_ENSEMBL_PATTERNS } from '../subworkflows/genomics/check_ensembl_patterns/main'
include { CUSTOM_MODE } from '../subworkflows/genomics/custom_mode/main'
include { GET_MATRIX } from '../subworkflows/genomics/get_matrix/main'
include { CREATE_SCVI_EMBEDDINGS_SCRNA } from '../subworkflows/genomics/create_scvi_embeddings_scRNA/main'
include { CONDA_ENV_EXISTS } from '../subworkflows/genomics/conda_env_exists/main'
include { MAP_TO_IMA_INTERPRET_SCRNA } from '../subworkflows/genomics/map_to_ima_interpret_scRNA/main'
include { ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES } from '../subworkflows/genomics/analyze_comparative_genomics_and_haplotypes/main'
include { ANALYZE_CHROMATIN_INTERACTIONS } from '../subworkflows/genomics/analyze_chromatin_interactions/main'
include { GENERATE_TRANSCRIPTFORMER_EMBEDDINGS } from '../subworkflows/genomics/generate_transcriptformer_embeddings/main'
include { GENERATE_EMBEDDINGS_WITH_STATE } from '../subworkflows/genomics/generate_embeddings_with_state/main'
include { GET_RNA_SEQ_ARCHS4 } from '../subworkflows/genomics/get_rna_seq_archs4/main'
include { LIST_GLYCOENGINEERING_RESOURCES } from '../subworkflows/glycoengineering/list_glycoengineering_resources/main'
include { FIND_N_GLYCOSYLATION_MOTIFS } from '../subworkflows/glycoengineering/find_n_glycosylation_motifs/main'
include { PREDICT_O_GLYCOSYLATION_HOTSPOTS } from '../subworkflows/glycoengineering/predict_o_glycosylation_hotspots/main'
include { TRACK_IMMUNE_CELLS_UNDER_FLOW } from '../subworkflows/immunology/track_immune_cells_under_flow/main'
include { ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS } from '../subworkflows/immunology/analyze_cytokine_production_in_cd4_tcells/main'
include { ANALYZE_CFSE_CELL_PROLIFERATION } from '../subworkflows/immunology/analyze_cfse_cell_proliferation/main'
include { SIMULATE_CELL_POPULATION } from '../subworkflows/immunology/simulate_cell_population/main'
include { ESTIMATE_CELL_CYCLE_PHASE_DURATIONS } from '../subworkflows/immunology/estimate_cell_cycle_phase_durations/main'
include { ISOLATE_PURIFY_IMMUNE_CELLS } from '../subworkflows/immunology/isolate_purify_immune_cells/main'
include { LOGISTIC_GROWTH } from '../subworkflows/immunology/logistic_growth/main'
include { ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE } from '../subworkflows/immunology/analyze_immunohistochemistry_image/main'
include { ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY } from '../subworkflows/immunology/analyze_atac_seq_differential_accessibility/main'
include { ANALYZE_EBV_ANTIBODY_TITERS } from '../subworkflows/immunology/analyze_ebv_antibody_titers/main'
include { ANALYZE_BACTERIAL_GROWTH_CURVE } from '../subworkflows/immunology/analyze_bacterial_growth_curve/main'
include { OBJECTIVE_FUNCTION } from '../subworkflows/immunology/objective_function/main'
include { ANALYZE_CNS_LESION_HISTOLOGY } from '../subworkflows/immunology/analyze_cns_lesion_histology/main'
include { TARGET } from '../subworkflows/lab_automation/target/main'
include { GET_PYLABROBOT_DOCUMENTATION_LIQUID } from '../subworkflows/lab_automation/get_pylabrobot_documentation_liquid/main'
include { TEST_PYLABROBOT_SCRIPT } from '../subworkflows/lab_automation/test_pylabrobot_script/main'
include { PICK_FIRST } from '../subworkflows/lab_automation/pick_first/main'
include { RUN_ASYNC } from '../subworkflows/lab_automation/run_async/main'
include { GET_PYLABROBOT_DOCUMENTATION_MATERIAL } from '../subworkflows/lab_automation/get_pylabrobot_documentation_material/main'
include { FETCH_SUPPLEMENTARY_INFO_FROM_DOI } from '../subworkflows/literature/fetch_supplementary_info_from_doi/main'
include { EXTRACT_URL_CONTENT } from '../subworkflows/literature/extract_url_content/main'
include { ADVANCED_WEB_SEARCH_CLAUDE } from '../subworkflows/literature/advanced_web_search_claude/main'
include { EXTRACT_PDF_CONTENT } from '../subworkflows/literature/extract_pdf_content/main'
include { MODEL_BACTERIAL_GROWTH_DYNAMICS } from '../subworkflows/microbiology/model_bacterial_growth_dynamics/main'
include { SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS } from '../subworkflows/microbiology/simulate_generalized_lotka_volterra_dynamics/main'
include { QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET } from '../subworkflows/microbiology/quantify_biofilm_biomass_crystal_violet/main'
include { COUNT_BACTERIAL_COLONIES } from '../subworkflows/microbiology/count_bacterial_colonies/main'
include { ANNOTATE_BACTERIAL_GENOME } from '../subworkflows/microbiology/annotate_bacterial_genome/main'
include { SIMULATE_MICROBIAL_POPULATION_DYNAMICS } from '../subworkflows/microbiology/simulate_microbial_population_dynamics/main'
include { VFA_PRODUCTION_MODEL } from '../subworkflows/microbiology/vfa_production_model/main'
include { PREDICT_RNA_SECONDARY_STRUCTURE } from '../subworkflows/microbiology/predict_rna_secondary_structure/main'
include { ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION } from '../subworkflows/microbiology/enumerate_bacterial_cfu_by_serial_dilution/main'
include { SEGMENT_AND_ANALYZE_MICROBIAL_CELLS } from '../subworkflows/microbiology/segment_and_analyze_microbial_cells/main'
include { BACTERIAL_DYNAMICS } from '../subworkflows/microbiology/bacterial_dynamics/main'
include { METHANE_YIELD_MODEL } from '../subworkflows/microbiology/methane_yield_model/main'
include { SEGMENT_CELLS_WITH_DEEP_LEARNING } from '../subworkflows/microbiology/segment_cells_with_deep_learning/main'
include { GLV_EQUATIONS } from '../subworkflows/microbiology/glv_equations/main'
include { ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS } from '../subworkflows/microbiology/analyze_arsenic_speciation_hplc_icpms/main'
include { OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS } from '../subworkflows/microbiology/optimize_anaerobic_digestion_process/main'
include { FIND_SEQUENCE_MUTATIONS } from '../subworkflows/molecular_biology/find_sequence_mutations/main'
include { FIND_RESTRICTION_ENZYMES } from '../subworkflows/molecular_biology/find_restriction_enzymes/main'
include { ANNOTATE_OPEN_READING_FRAMES } from '../subworkflows/molecular_biology/annotate_open_reading_frames/main'
include { DESIGN_GOLDEN_GATE_OLIGOS } from '../subworkflows/molecular_biology/design_golden_gate_oligos/main'
include { DESIGN_VERIFICATION_PRIMERS } from '../subworkflows/molecular_biology/design_verification_primers/main'
include { GOLDEN_GATE_ASSEMBLY } from '../subworkflows/molecular_biology/golden_gate_assembly/main'
include { GET_REFSEQ_ID } from '../subworkflows/molecular_biology/get_refseq_id/main'
include { GET_GENE_CODING_SEQUENCE } from '../subworkflows/molecular_biology/get_gene_coding_sequence/main'
include { PCR_SIMPLE } from '../subworkflows/molecular_biology/pcr_simple/main'
include { IS_POSITION_COVERED } from '../subworkflows/molecular_biology/is_position_covered/main'
include { GET_CODING_SEQUENCES } from '../subworkflows/molecular_biology/get_coding_sequences/main'
include { REVERSE_COMPLEMENT } from '../subworkflows/molecular_biology/reverse_complement/main'
include { FIND_RESTRICTION_SITES } from '../subworkflows/molecular_biology/find_restriction_sites/main'
include { FIND_ORFS_IN_FRAME } from '../subworkflows/molecular_biology/find_orfs_in_frame/main'
include { ALIGN_SEQUENCES } from '../subworkflows/molecular_biology/align_sequences/main'
include { GET_PLASMID_SEQUENCE } from '../subworkflows/molecular_biology/get_plasmid_sequence/main'
include { GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL } from '../subworkflows/molecular_biology/get_golden_gate_assembly_protocol/main'
include { MERGE_OVERLAPPING_REGIONS } from '../subworkflows/molecular_biology/merge_overlapping_regions/main'
include { DESIGN_KNOCKOUT_SGRNA } from '../subworkflows/molecular_biology/design_knockout_sgrna/main'
include { GET_OLIGO_ANNEALING_PROTOCOL } from '../subworkflows/molecular_biology/get_oligo_annealing_protocol/main'
include { GET_BACTERIAL_TRANSFORMATION_PROTOCOL } from '../subworkflows/molecular_biology/get_bacterial_transformation_protocol/main'
include { DIGEST_SEQUENCE } from '../subworkflows/molecular_biology/digest_sequence/main'
include { ANNOTATE_PLASMID } from '../subworkflows/molecular_biology/annotate_plasmid/main'
include { IS_REGION_FULLY_COVERED } from '../subworkflows/molecular_biology/is_region_fully_covered/main'
include { DESIGN_PRIMER } from '../subworkflows/molecular_biology/design_primer/main'
include { SEARCH_GENE } from '../subworkflows/molecular_biology/search_gene/main'
include { ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY } from '../subworkflows/pathology/analyze_aortic_diameter_and_geometry/main'
include { ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2 } from '../subworkflows/pathology/analyze_intracellular_calcium_with_rhod2/main'
include { ANALYZE_THROMBUS_HISTOLOGY } from '../subworkflows/pathology/analyze_thrombus_histology/main'
include { ANALYZE_ATP_LUMINESCENCE_ASSAY } from '../subworkflows/pathology/analyze_atp_luminescence_assay/main'
include { ANALYZE_BONE_MICROCT_MORPHOMETRY } from '../subworkflows/pathology/analyze_bone_microct_morphometry/main'
include { QUANTIFY_CORNEAL_NERVE_FIBERS } from '../subworkflows/pathology/quantify_corneal_nerve_fibers/main'
include { SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES } from '../subworkflows/pathology/segment_and_quantify_cells_in_multiplexed_images/main'
include { ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION } from '../subworkflows/pharmacology/analyze_radiolabeled_antibody_biodistribution/main'
include { ANALYZE_WESTERN_BLOT } from '../subworkflows/pharmacology/analyze_western_blot/main'
include { ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS } from '../subworkflows/pharmacology/analyze_accelerated_stability_of_pharmaceutical_formulations/main'
include { ADMET_PRED } from '../subworkflows/pharmacology/ADMET_pred/main'
include { RUN_DIFFDOCK_WITH_SMILES } from '../subworkflows/pharmacology/run_diffdock_with_smiles/main'
include { CALCULATE_PHYSICOCHEMICAL_PROPERTIES } from '../subworkflows/pharmacology/calculate_physicochemical_properties/main'
include { ANALYZE_FDA_SAFETY_SIGNALS } from '../subworkflows/pharmacology/analyze_fda_safety_signals/main'
include { RUN_AUTOSITE } from '../subworkflows/pharmacology/run_autosite/main'
include { GET_FDA_DRUG_LABEL_INFO } from '../subworkflows/pharmacology/get_fda_drug_label_info/main'
include { ANALYZE_INTERACTION_MECHANISMS } from '../subworkflows/pharmacology/analyze_interaction_mechanisms/main'
include { ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY } from '../subworkflows/pharmacology/estimate_alpha_particle_radiotherapy_dosimetry/main'
include { ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION } from '../subworkflows/pharmacology/analyze_xenograft_tumor_growth_inhibition/main'
include { PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE } from '../subworkflows/pharmacology/predict_binding_affinity_protein_1d_sequence/main'
include { DOCKING_AUTODOCK_VINA } from '../subworkflows/pharmacology/docking_autodock_vina/main'
include { CHECK_FDA_DRUG_RECALLS } from '../subworkflows/pharmacology/check_fda_drug_recalls/main'
include { CHECK_DRUG_COMBINATION_SAFETY } from '../subworkflows/pharmacology/check_drug_combination_safety/main'
include { APPLY_VCOG_GRADE } from '../subworkflows/pharmacology/apply_vcog_grade/main'
include { RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY } from '../subworkflows/pharmacology/run_3d_chondrogenic_aggregate_assay/main'
include { SIGMOID } from '../subworkflows/pharmacology/sigmoid/main'
include { BI_EXP_MODEL } from '../subworkflows/pharmacology/bi_exp_model/main'
include { PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS } from '../subworkflows/pharmacology/perform_mwas_cyp2c19_metabolizer_status/main'
include { RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN } from '../subworkflows/pharmacology/retrieve_topk_repurposing_drugs_from_disease_txgnn/main'
include { FIND_ALTERNATIVE_DRUGS_DDINTER } from '../subworkflows/pharmacology/find_alternative_drugs_ddinter/main'
include { PREDICT_ADMET_PROPERTIES } from '../subworkflows/pharmacology/predict_admet_properties/main'
include { GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE } from '../subworkflows/pharmacology/grade_adverse_events_using_vcog_ctcae/main'
include { ANALYZE_FATTY_ACID_COMPOSITION_BY_GC } from '../subworkflows/physiology/analyze_fatty_acid_composition_by_gc/main'
include { ANALYZE_CILIARY_BEAT_FREQUENCY } from '../subworkflows/physiology/analyze_ciliary_beat_frequency/main'
include { ANALYZE_ABR_WAVEFORM_P1_METRICS } from '../subworkflows/physiology/analyze_abr_waveform_p1_metrics/main'
include { CALCULATE_BRAIN_ADC_MAP } from '../subworkflows/physiology/calculate_brain_adc_map/main'
include { MONO_EXP_MODEL } from '../subworkflows/physiology/mono_exp_model/main'
include { ANALYZE_HEMODYNAMIC_DATA } from '../subworkflows/physiology/analyze_hemodynamic_data/main'
include { PERFORM_COSINOR_ANALYSIS } from '../subworkflows/physiology/perform_cosinor_analysis/main'
include { PK_ODE_SYSTEM } from '../subworkflows/physiology/pk_ode_system/main'
include { RECONSTRUCT_3D_FACE_FROM_MRI } from '../subworkflows/physiology/reconstruct_3d_face_from_mri/main'
include { COSINOR_MODEL } from '../subworkflows/physiology/cosinor_model/main'
include { ANALYZE_PROTEIN_COLOCALIZATION } from '../subworkflows/physiology/analyze_protein_colocalization/main'
include { SIMULATE_THYROID_HORMONE_PHARMACOKINETICS } from '../subworkflows/physiology/simulate_thyroid_hormone_pharmacokinetics/main'
include { QUANTIFY_AMYLOID_BETA_PLAQUES } from '../subworkflows/physiology/quantify_amyloid_beta_plaques/main'
include { ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS } from '../subworkflows/physiology/analyze_endolysosomal_calcium_dynamics/main'
include { SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK } from '../subworkflows/synthetic_biology/simulate_gene_circuit_with_growth_feedback/main'
include { GOMPERTZ_MODEL } from '../subworkflows/synthetic_biology/gompertz_model/main'
include { ANALYZE_BACTERIAL_GROWTH_RATE } from '../subworkflows/synthetic_biology/analyze_bacterial_growth_rate/main'
include { CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL } from '../subworkflows/synthetic_biology/create_biochemical_network_sbml_model/main'
include { ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY } from '../subworkflows/synthetic_biology/engineer_bacterial_genome_for_therapeutic_delivery/main'
include { GENE_CIRCUIT_ODES } from '../subworkflows/synthetic_biology/gene_circuit_odes/main'
include { ANALYZE_BIFURCATION_DIAGRAM } from '../subworkflows/synthetic_biology/analyze_bifurcation_diagram/main'
include { IDENTIFY_FAS_FUNCTIONAL_DOMAINS } from '../subworkflows/synthetic_biology/identify_fas_functional_domains/main'
include { HAMMING_DISTANCE } from '../subworkflows/synthetic_biology/hamming_distance/main'
include { ANALYZE_BARCODE_SEQUENCING_DATA } from '../subworkflows/synthetic_biology/analyze_barcode_sequencing_data/main'
include { OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION } from '../subworkflows/synthetic_biology/optimize_codons_for_heterologous_expression/main'
include { SIMULATE_PROTEIN_SIGNALING_NETWORK } from '../subworkflows/systems_biology/simulate_protein_signaling_network/main'
include { RAS_ODE_SYSTEM } from '../subworkflows/systems_biology/ras_ode_system/main'
include { SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS } from '../subworkflows/systems_biology/simulate_renin_angiotensin_system_dynamics/main'
include { ODE_SYSTEM } from '../subworkflows/systems_biology/ode_system/main'
include { SIMULATE_METABOLIC_NETWORK_PERTURBATION } from '../subworkflows/systems_biology/simulate_metabolic_network_perturbation/main'
include { COMPARE_PROTEIN_STRUCTURES } from '../subworkflows/systems_biology/compare_protein_structures/main'
include { PERFORM_FLUX_BALANCE_ANALYSIS } from '../subworkflows/systems_biology/perform_flux_balance_analysis/main'
include { MASS_ACTION_KINETICS } from '../subworkflows/systems_biology/mass_action_kinetics/main'
include { MODEL_PROTEIN_DIMERIZATION_NETWORK } from '../subworkflows/systems_biology/model_protein_dimerization_network/main'
include { HILL_FUNCTION } from '../subworkflows/systems_biology/hill_function/main'
include { DIMERIZATION_ODES } from '../subworkflows/systems_biology/dimerization_odes/main'
include { QUERY_CHATNT } from '../subworkflows/systems_biology/query_chatnt/main'

params.test_data = "${projectDir}/test_data"
params.outdir = "${projectDir}/test_results"
params.test = 'all'


workflow TEST_DOSE_RESPONSE {
    ch_input = Channel.of([
        [id: 'test_dose_response'],
        file("${params.test_data}/placeholder.txt")
    ])
    DOSE_RESPONSE(ch_input)
    DOSE_RESPONSE.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_PROTEIN_CONSERVATION {
    ch_input = Channel.of([
        [id: 'test_analyze_protein_conservation'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_PROTEIN_CONSERVATION(ch_input)
    ANALYZE_PROTEIN_CONSERVATION.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CIRCULAR_DICHROISM_SPECTRA {
    ch_input = Channel.of([
        [id: 'test_analyze_circular_dichroism_spectra'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CIRCULAR_DICHROISM_SPECTRA(ch_input)
    ANALYZE_CIRCULAR_DICHROISM_SPECTRA.out.results.view { "Result: $it" }
}


workflow TEST_MICHAELIS_MENTEN {
    ch_input = Channel.of([
        [id: 'test_michaelis_menten'],
        file("${params.test_data}/placeholder.txt")
    ])
    MICHAELIS_MENTEN(ch_input)
    MICHAELIS_MENTEN.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_ITC_BINDING_THERMODYNAMICS {
    ch_input = Channel.of([
        [id: 'test_analyze_itc_binding_thermodynamics'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_ITC_BINDING_THERMODYNAMICS(ch_input)
    ANALYZE_ITC_BINDING_THERMODYNAMICS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES {
    ch_input = Channel.of([
        [id: 'test_analyze_rna_secondary_structure_features'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES(ch_input)
    ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES.out.results.view { "Result: $it" }
}


workflow TEST_ONE_SITE_MODEL {
    ch_input = Channel.of([
        [id: 'test_one_site_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    ONE_SITE_MODEL(ch_input)
    ONE_SITE_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_PROTEASE_KINETICS {
    ch_input = Channel.of([
        [id: 'test_analyze_protease_kinetics'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_PROTEASE_KINETICS(ch_input)
    ANALYZE_PROTEASE_KINETICS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_ENZYME_KINETICS_ASSAY {
    ch_input = Channel.of([
        [id: 'test_analyze_enzyme_kinetics_assay'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_ENZYME_KINETICS_ASSAY(ch_input)
    ANALYZE_ENZYME_KINETICS_ASSAY.out.results.view { "Result: $it" }
}


workflow TEST_ZERO_ORDER {
    ch_input = Channel.of([
        [id: 'test_zero_order'],
        file("${params.test_data}/placeholder.txt")
    ])
    ZERO_ORDER(ch_input)
    ZERO_ORDER.out.results.view { "Result: $it" }
}


workflow TEST_FIRST_ORDER {
    ch_input = Channel.of([
        [id: 'test_first_order'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIRST_ORDER(ch_input)
    FIRST_ORDER.out.results.view { "Result: $it" }
}


workflow TEST_KORSMEYER_PEPPAS {
    ch_input = Channel.of([
        [id: 'test_korsmeyer_peppas'],
        file("${params.test_data}/placeholder.txt")
    ])
    KORSMEYER_PEPPAS(ch_input)
    KORSMEYER_PEPPAS.out.results.view { "Result: $it" }
}


workflow TEST_PERFORM_CRISPR_CAS9_GENOME_EDITING {
    ch_input = Channel.of([
        [id: 'test_perform_crispr_cas9_genome_editing'],
        file("${params.test_data}/placeholder.txt")
    ])
    PERFORM_CRISPR_CAS9_GENOME_EDITING(ch_input)
    PERFORM_CRISPR_CAS9_GENOME_EDITING.out.results.view { "Result: $it" }
}


workflow TEST_DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES {
    ch_input = Channel.of([
        [id: 'test_decode_behavior_from_neural_trajectories'],
        file("${params.test_data}/placeholder.txt")
    ])
    DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES(ch_input)
    DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_WHOLE_CELL_ODE_MODEL {
    ch_input = Channel.of([
        [id: 'test_simulate_whole_cell_ode_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_WHOLE_CELL_ODE_MODEL(ch_input)
    SIMULATE_WHOLE_CELL_ODE_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_DEFAULT_WHOLE_CELL_MODEL {
    ch_input = Channel.of([
        [id: 'test_default_whole_cell_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    DEFAULT_WHOLE_CELL_MODEL(ch_input)
    DEFAULT_WHOLE_CELL_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CALCIUM_IMAGING_DATA {
    ch_input = Channel.of([
        [id: 'test_analyze_calcium_imaging_data'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CALCIUM_IMAGING_DATA(ch_input)
    ANALYZE_CALCIUM_IMAGING_DATA.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CELL_MIGRATION_METRICS {
    ch_input = Channel.of([
        [id: 'test_analyze_cell_migration_metrics'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CELL_MIGRATION_METRICS(ch_input)
    ANALYZE_CELL_MIGRATION_METRICS.out.results.view { "Result: $it" }
}


workflow TEST_HIGUCHI {
    ch_input = Channel.of([
        [id: 'test_higuchi'],
        file("${params.test_data}/placeholder.txt")
    ])
    HIGUCHI(ch_input)
    HIGUCHI.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS {
    ch_input = Channel.of([
        [id: 'test_analyze_in_vitro_drug_release_kinetics'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS(ch_input)
    ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS.out.results.view { "Result: $it" }
}


workflow TEST_EXP_DECAY {
    ch_input = Channel.of([
        [id: 'test_exp_decay'],
        file("${params.test_data}/placeholder.txt")
    ])
    EXP_DECAY(ch_input)
    EXP_DECAY.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_MYOFIBER_MORPHOLOGY {
    ch_input = Channel.of([
        [id: 'test_analyze_myofiber_morphology'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_MYOFIBER_MORPHOLOGY(ch_input)
    ANALYZE_MYOFIBER_MORPHOLOGY.out.results.view { "Result: $it" }
}


workflow TEST_CALCULATE_SIMILARITY_METRICS {
    ch_input = Channel.of([
        [id: 'test_calculate_similarity_metrics'],
        file("${params.test_data}/placeholder.txt")
    ])
    CALCULATE_SIMILARITY_METRICS(ch_input)
    CALCULATE_SIMILARITY_METRICS.out.results.view { "Result: $it" }
}


workflow TEST_PATCHED_TORCH_LOAD {
    ch_input = Channel.of([
        [id: 'test_patched_torch_load'],
        file("${params.test_data}/placeholder.txt")
    ])
    PATCHED_TORCH_LOAD(ch_input)
    PATCHED_TORCH_LOAD.out.results.view { "Result: $it" }
}


workflow TEST_CHECK_MODEL_FILES_EXIST {
    ch_input = Channel.of([
        [id: 'test_check_model_files_exist'],
        file("${params.test_data}/placeholder.txt")
    ])
    CHECK_MODEL_FILES_EXIST(ch_input)
    CHECK_MODEL_FILES_EXIST.out.results.view { "Result: $it" }
}


workflow TEST_QUICK_RIGID_REGISTRATION {
    ch_input = Channel.of([
        [id: 'test_quick_rigid_registration'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUICK_RIGID_REGISTRATION(ch_input)
    QUICK_RIGID_REGISTRATION.out.results.view { "Result: $it" }
}


workflow TEST_SEGMENT_WITH_NN_UNET {
    ch_input = Channel.of([
        [id: 'test_segment_with_nn_unet'],
        file("${params.test_data}/placeholder.txt")
    ])
    SEGMENT_WITH_NN_UNET(ch_input)
    SEGMENT_WITH_NN_UNET.out.results.view { "Result: $it" }
}


workflow TEST_SAVE_IMAGE {
    ch_input = Channel.of([
        [id: 'test_save_image'],
        file("${params.test_data}/placeholder.txt")
    ])
    SAVE_IMAGE(ch_input)
    SAVE_IMAGE.out.results.view { "Result: $it" }
}


workflow TEST_SPLIT_MODALITIES {
    ch_input = Channel.of([
        [id: 'test_split_modalities'],
        file("${params.test_data}/placeholder.txt")
    ])
    SPLIT_MODALITIES(ch_input)
    SPLIT_MODALITIES.out.results.view { "Result: $it" }
}


workflow TEST_PREPARE_INPUT_FOR_NNUNET {
    ch_input = Channel.of([
        [id: 'test_prepare_input_for_nnunet'],
        file("${params.test_data}/placeholder.txt")
    ])
    PREPARE_INPUT_FOR_NNUNET(ch_input)
    PREPARE_INPUT_FOR_NNUNET.out.results.view { "Result: $it" }
}


workflow TEST_PREPROCESS_IMAGE {
    ch_input = Channel.of([
        [id: 'test_preprocess_image'],
        file("${params.test_data}/placeholder.txt")
    ])
    PREPROCESS_IMAGE(ch_input)
    PREPROCESS_IMAGE.out.results.view { "Result: $it" }
}


workflow TEST_QUICK_DEFORMABLE_REGISTRATION {
    ch_input = Channel.of([
        [id: 'test_quick_deformable_registration'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUICK_DEFORMABLE_REGISTRATION(ch_input)
    QUICK_DEFORMABLE_REGISTRATION.out.results.view { "Result: $it" }
}


workflow TEST_CREATE_DEFORMABLE_TRANSFORM {
    ch_input = Channel.of([
        [id: 'test_create_deformable_transform'],
        file("${params.test_data}/placeholder.txt")
    ])
    CREATE_DEFORMABLE_TRANSFORM(ch_input)
    CREATE_DEFORMABLE_TRANSFORM.out.results.view { "Result: $it" }
}


workflow TEST_BATCH_REGISTER_IMAGES {
    ch_input = Channel.of([
        [id: 'test_batch_register_images'],
        file("${params.test_data}/placeholder.txt")
    ])
    BATCH_REGISTER_IMAGES(ch_input)
    BATCH_REGISTER_IMAGES.out.results.view { "Result: $it" }
}


workflow TEST_VERIFY_NIFTI_INPUT {
    ch_input = Channel.of([
        [id: 'test_verify_nifti_input'],
        file("${params.test_data}/placeholder.txt")
    ])
    VERIFY_NIFTI_INPUT(ch_input)
    VERIFY_NIFTI_INPUT.out.results.view { "Result: $it" }
}


workflow TEST_SETUP_NNUNET_ENVIRONMENT {
    ch_input = Channel.of([
        [id: 'test_setup_nnunet_environment'],
        file("${params.test_data}/placeholder.txt")
    ])
    SETUP_NNUNET_ENVIRONMENT(ch_input)
    SETUP_NNUNET_ENVIRONMENT.out.results.view { "Result: $it" }
}


workflow TEST_REGISTER_IMAGES {
    ch_input = Channel.of([
        [id: 'test_register_images'],
        file("${params.test_data}/placeholder.txt")
    ])
    REGISTER_IMAGES(ch_input)
    REGISTER_IMAGES.out.results.view { "Result: $it" }
}


workflow TEST_CREATE_RIGID_TRANSFORM {
    ch_input = Channel.of([
        [id: 'test_create_rigid_transform'],
        file("${params.test_data}/placeholder.txt")
    ])
    CREATE_RIGID_TRANSFORM(ch_input)
    CREATE_RIGID_TRANSFORM.out.results.view { "Result: $it" }
}


workflow TEST_COMMAND_ITERATION {
    ch_input = Channel.of([
        [id: 'test_command_iteration'],
        file("${params.test_data}/placeholder.txt")
    ])
    COMMAND_ITERATION(ch_input)
    COMMAND_ITERATION.out.results.view { "Result: $it" }
}


workflow TEST_SETUP_REGISTRATION_METHOD {
    ch_input = Channel.of([
        [id: 'test_setup_registration_method'],
        file("${params.test_data}/placeholder.txt")
    ])
    SETUP_REGISTRATION_METHOD(ch_input)
    SETUP_REGISTRATION_METHOD.out.results.view { "Result: $it" }
}


workflow TEST_CREATE_SEGMENTATION_VISUALIZATION {
    ch_input = Channel.of([
        [id: 'test_create_segmentation_visualization'],
        file("${params.test_data}/placeholder.txt")
    ])
    CREATE_SEGMENTATION_VISUALIZATION(ch_input)
    CREATE_SEGMENTATION_VISUALIZATION.out.results.view { "Result: $it" }
}


workflow TEST_LOAD_IMAGE {
    ch_input = Channel.of([
        [id: 'test_load_image'],
        file("${params.test_data}/placeholder.txt")
    ])
    LOAD_IMAGE(ch_input)
    LOAD_IMAGE.out.results.view { "Result: $it" }
}


workflow TEST_QUICK_AFFINE_REGISTRATION {
    ch_input = Channel.of([
        [id: 'test_quick_affine_registration'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUICK_AFFINE_REGISTRATION(ch_input)
    QUICK_AFFINE_REGISTRATION.out.results.view { "Result: $it" }
}


workflow TEST_CREATE_AFFINE_TRANSFORM {
    ch_input = Channel.of([
        [id: 'test_create_affine_transform'],
        file("${params.test_data}/placeholder.txt")
    ])
    CREATE_AFFINE_TRANSFORM(ch_input)
    CREATE_AFFINE_TRANSFORM.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_TISSUE_DEFORMATION_FLOW {
    ch_input = Channel.of([
        [id: 'test_analyze_tissue_deformation_flow'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_TISSUE_DEFORMATION_FLOW(ch_input)
    ANALYZE_TISSUE_DEFORMATION_FLOW.out.results.view { "Result: $it" }
}


workflow TEST_PREDICT_PROTEIN_DISORDER_REGIONS {
    ch_input = Channel.of([
        [id: 'test_predict_protein_disorder_regions'],
        file("${params.test_data}/placeholder.txt")
    ])
    PREDICT_PROTEIN_DISORDER_REGIONS(ch_input)
    PREDICT_PROTEIN_DISORDER_REGIONS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON {
    ch_input = Channel.of([
        [id: 'test_analyze_cell_morphology_and_cytoskeleton'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON(ch_input)
    ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_DDR_NETWORK_IN_CANCER {
    ch_input = Channel.of([
        [id: 'test_analyze_ddr_network_in_cancer'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_DDR_NETWORK_IN_CANCER(ch_input)
    ANALYZE_DDR_NETWORK_IN_CANCER.out.results.view { "Result: $it" }
}


workflow TEST_DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS {
    ch_input = Channel.of([
        [id: 'test_detect_and_annotate_somatic_mutations'],
        file("${params.test_data}/placeholder.txt")
    ])
    DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS(ch_input)
    DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS {
    ch_input = Channel.of([
        [id: 'test_analyze_cell_senescence_and_apoptosis'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS(ch_input)
    ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS.out.results.view { "Result: $it" }
}


workflow TEST_NORM_CHR {
    ch_input = Channel.of([
        [id: 'test_norm_chr'],
        file("${params.test_data}/placeholder.txt")
    ])
    NORM_CHR(ch_input)
    NORM_CHR.out.results.view { "Result: $it" }
}


workflow TEST_DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS {
    ch_input = Channel.of([
        [id: 'test_detect_and_characterize_structural_variations'],
        file("${params.test_data}/placeholder.txt")
    ])
    DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS(ch_input)
    DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS {
    ch_input = Channel.of([
        [id: 'test_analyze_copy_number_purity_ploidy_and_focal_events'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS(ch_input)
    ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS.out.results.view { "Result: $it" }
}


workflow TEST_PERFORM_GENE_EXPRESSION_NMF_ANALYSIS {
    ch_input = Channel.of([
        [id: 'test_perform_gene_expression_nmf_analysis'],
        file("${params.test_data}/placeholder.txt")
    ])
    PERFORM_GENE_EXPRESSION_NMF_ANALYSIS(ch_input)
    PERFORM_GENE_EXPRESSION_NMF_ANALYSIS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL {
    ch_input = Channel.of([
        [id: 'test_analyze_mitochondrial_morphology_and_potential'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL(ch_input)
    ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    ch_input = Channel.of([
        [id: 'test_analyze_flow_cytometry_immunophenotyping'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING(ch_input)
    ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING.out.results.view { "Result: $it" }
}


workflow TEST_QUANTIFY_AND_CLUSTER_CELL_MOTILITY {
    ch_input = Channel.of([
        [id: 'test_quantify_and_cluster_cell_motility'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUANTIFY_AND_CLUSTER_CELL_MOTILITY(ch_input)
    QUANTIFY_AND_CLUSTER_CELL_MOTILITY.out.results.view { "Result: $it" }
}


workflow TEST_QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY {
    ch_input = Channel.of([
        [id: 'test_quantify_cell_cycle_phases_from_microscopy'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY(ch_input)
    QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY.out.results.view { "Result: $it" }
}


workflow TEST_PERFORM_FACS_CELL_SORTING {
    ch_input = Channel.of([
        [id: 'test_perform_facs_cell_sorting'],
        file("${params.test_data}/placeholder.txt")
    ])
    PERFORM_FACS_CELL_SORTING(ch_input)
    PERFORM_FACS_CELL_SORTING.out.results.view { "Result: $it" }
}


workflow TEST_REDUCE_TOKENS {
    ch_input = Channel.of([
        [id: 'test_reduce_tokens'],
        file("${params.test_data}/placeholder.txt")
    ])
    REDUCE_TOKENS(ch_input)
    REDUCE_TOKENS.out.results.view { "Result: $it" }
}


workflow TEST_GET_HPO_NAMES {
    ch_input = Channel.of([
        [id: 'test_get_hpo_names'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_HPO_NAMES(ch_input)
    GET_HPO_NAMES.out.results.view { "Result: $it" }
}


workflow TEST_REGION_TO_CCRE_SCREEN {
    ch_input = Channel.of([
        [id: 'test_region_to_ccre_screen'],
        file("${params.test_data}/placeholder.txt")
    ])
    REGION_TO_CCRE_SCREEN(ch_input)
    REGION_TO_CCRE_SCREEN.out.results.view { "Result: $it" }
}


workflow TEST_BLAST_SEQUENCE {
    ch_input = Channel.of([
        [id: 'test_blast_sequence'],
        file("${params.test_data}/placeholder.txt")
    ])
    BLAST_SEQUENCE(ch_input)
    BLAST_SEQUENCE.out.results.view { "Result: $it" }
}


workflow TEST_GET_GENES_NEAR_CCRE {
    ch_input = Channel.of([
        [id: 'test_get_genes_near_ccre'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_GENES_NEAR_CCRE(ch_input)
    GET_GENES_NEAR_CCRE.out.results.view { "Result: $it" }
}


workflow TEST_LIFTOVER_COORDINATES {
    ch_input = Channel.of([
        [id: 'test_liftover_coordinates'],
        file("${params.test_data}/placeholder.txt")
    ])
    LIFTOVER_COORDINATES(ch_input)
    LIFTOVER_COORDINATES.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_PROTEIN_PHYLOGENY {
    ch_input = Channel.of([
        [id: 'test_analyze_protein_phylogeny'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_PROTEIN_PHYLOGENY(ch_input)
    ANALYZE_PROTEIN_PHYLOGENY.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CAS9_MUTATION_OUTCOMES {
    ch_input = Channel.of([
        [id: 'test_analyze_cas9_mutation_outcomes'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CAS9_MUTATION_OUTCOMES(ch_input)
    ANALYZE_CAS9_MUTATION_OUTCOMES.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CRISPR_GENOME_EDITING {
    ch_input = Channel.of([
        [id: 'test_analyze_crispr_genome_editing'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CRISPR_GENOME_EDITING(ch_input)
    ANALYZE_CRISPR_GENOME_EDITING.out.results.view { "Result: $it" }
}


workflow TEST_IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES {
    ch_input = Channel.of([
        [id: 'test_identify_transcription_factor_binding_sites'],
        file("${params.test_data}/placeholder.txt")
    ])
    IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES(ch_input)
    IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES.out.results.view { "Result: $it" }
}


workflow TEST_FORWARD {
    ch_input = Channel.of([
        [id: 'test_forward'],
        file("${params.test_data}/placeholder.txt")
    ])
    FORWARD(ch_input)
    FORWARD.out.results.view { "Result: $it" }
}


workflow TEST_BAYESIAN_FINEMAPPING_WITH_DEEP_VI {
    ch_input = Channel.of([
        [id: 'test_bayesian_finemapping_with_deep_vi'],
        file("${params.test_data}/placeholder.txt")
    ])
    BAYESIAN_FINEMAPPING_WITH_DEEP_VI(ch_input)
    BAYESIAN_FINEMAPPING_WITH_DEEP_VI.out.results.view { "Result: $it" }
}


workflow TEST_FIT_GENOMIC_PREDICTION_MODEL {
    ch_input = Channel.of([
        [id: 'test_fit_genomic_prediction_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIT_GENOMIC_PREDICTION_MODEL(ch_input)
    FIT_GENOMIC_PREDICTION_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_ELBO_LOSS {
    ch_input = Channel.of([
        [id: 'test_elbo_loss'],
        file("${params.test_data}/placeholder.txt")
    ])
    ELBO_LOSS(ch_input)
    ELBO_LOSS.out.results.view { "Result: $it" }
}


workflow TEST_PERFORM_PCR_AND_GEL_ELECTROPHORESIS {
    ch_input = Channel.of([
        [id: 'test_perform_pcr_and_gel_electrophoresis'],
        file("${params.test_data}/placeholder.txt")
    ])
    PERFORM_PCR_AND_GEL_ELECTROPHORESIS(ch_input)
    PERFORM_PCR_AND_GEL_ELECTROPHORESIS.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_DEMOGRAPHIC_HISTORY {
    ch_input = Channel.of([
        [id: 'test_simulate_demographic_history'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_DEMOGRAPHIC_HISTORY(ch_input)
    SIMULATE_DEMOGRAPHIC_HISTORY.out.results.view { "Result: $it" }
}


workflow TEST_UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS {
    ch_input = Channel.of([
        [id: 'test_unsupervised_celltype_transfer_between_scRNA_datasets'],
        file("${params.test_data}/placeholder.txt")
    ])
    UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS(ch_input)
    UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS.out.results.view { "Result: $it" }
}


workflow TEST_ANNOTATE_CELLTYPE_SCRNA {
    ch_input = Channel.of([
        [id: 'test_annotate_celltype_scRNA'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANNOTATE_CELLTYPE_SCRNA(ch_input)
    ANNOTATE_CELLTYPE_SCRNA.out.results.view { "Result: $it" }
}


workflow TEST_CREATE_HARMONY_EMBEDDINGS_SCRNA {
    ch_input = Channel.of([
        [id: 'test_create_harmony_embeddings_scRNA'],
        file("${params.test_data}/placeholder.txt")
    ])
    CREATE_HARMONY_EMBEDDINGS_SCRNA(ch_input)
    CREATE_HARMONY_EMBEDDINGS_SCRNA.out.results.view { "Result: $it" }
}


workflow TEST_CREATE_PANHUMANPY_ENV {
    ch_input = Channel.of([
        [id: 'test_create_panhumanpy_env'],
        file("${params.test_data}/placeholder.txt")
    ])
    CREATE_PANHUMANPY_ENV(ch_input)
    CREATE_PANHUMANPY_ENV.out.results.view { "Result: $it" }
}


workflow TEST_GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST {
    ch_input = Channel.of([
        [id: 'test_get_gene_set_enrichment_analysis_supported_database_list'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST(ch_input)
    GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_GENOMIC_REGION_OVERLAP {
    ch_input = Channel.of([
        [id: 'test_analyze_genomic_region_overlap'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_GENOMIC_REGION_OVERLAP(ch_input)
    ANALYZE_GENOMIC_REGION_OVERLAP.out.results.view { "Result: $it" }
}


workflow TEST_INTERSPECIES_GENE_CONVERSION {
    ch_input = Channel.of([
        [id: 'test_interspecies_gene_conversion'],
        file("${params.test_data}/placeholder.txt")
    ])
    INTERSPECIES_GENE_CONVERSION(ch_input)
    INTERSPECIES_GENE_CONVERSION.out.results.view { "Result: $it" }
}


workflow TEST_GET_UCE_EMBEDDINGS_SCRNA {
    ch_input = Channel.of([
        [id: 'test_get_uce_embeddings_scRNA'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_UCE_EMBEDDINGS_SCRNA(ch_input)
    GET_UCE_EMBEDDINGS_SCRNA.out.results.view { "Result: $it" }
}


workflow TEST_PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2 {
    ch_input = Channel.of([
        [id: 'test_perform_chipseq_peak_calling_with_macs2'],
        file("${params.test_data}/placeholder.txt")
    ])
    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2(ch_input)
    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2.out.results.view { "Result: $it" }
}


workflow TEST_IS_MODEL_DOWNLOADED {
    ch_input = Channel.of([
        [id: 'test_is_model_downloaded'],
        file("${params.test_data}/placeholder.txt")
    ])
    IS_MODEL_DOWNLOADED(ch_input)
    IS_MODEL_DOWNLOADED.out.results.view { "Result: $it" }
}


workflow TEST_GENE_SET_ENRICHMENT_ANALYSIS {
    ch_input = Channel.of([
        [id: 'test_gene_set_enrichment_analysis'],
        file("${params.test_data}/placeholder.txt")
    ])
    GENE_SET_ENRICHMENT_ANALYSIS(ch_input)
    GENE_SET_ENRICHMENT_ANALYSIS.out.results.view { "Result: $it" }
}


workflow TEST_FIND_ENRICHED_MOTIFS_WITH_HOMER {
    ch_input = Channel.of([
        [id: 'test_find_enriched_motifs_with_homer'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIND_ENRICHED_MOTIFS_WITH_HOMER(ch_input)
    FIND_ENRICHED_MOTIFS_WITH_HOMER.out.results.view { "Result: $it" }
}


workflow TEST_GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS {
    ch_input = Channel.of([
        [id: 'test_generate_gene_embeddings_with_ESM_models'],
        file("${params.test_data}/placeholder.txt")
    ])
    GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS(ch_input)
    GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS.out.results.view { "Result: $it" }
}


workflow TEST_ANNOTATE_CELLTYPE_WITH_PANHUMANPY {
    ch_input = Channel.of([
        [id: 'test_annotate_celltype_with_panhumanpy'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANNOTATE_CELLTYPE_WITH_PANHUMANPY(ch_input)
    ANNOTATE_CELLTYPE_WITH_PANHUMANPY.out.results.view { "Result: $it" }
}


workflow TEST_CHECK_ENSEMBL_PATTERNS {
    ch_input = Channel.of([
        [id: 'test_check_ensembl_patterns'],
        file("${params.test_data}/placeholder.txt")
    ])
    CHECK_ENSEMBL_PATTERNS(ch_input)
    CHECK_ENSEMBL_PATTERNS.out.results.view { "Result: $it" }
}


workflow TEST_CUSTOM_MODE {
    ch_input = Channel.of([
        [id: 'test_custom_mode'],
        file("${params.test_data}/placeholder.txt")
    ])
    CUSTOM_MODE(ch_input)
    CUSTOM_MODE.out.results.view { "Result: $it" }
}


workflow TEST_GET_MATRIX {
    ch_input = Channel.of([
        [id: 'test_get_matrix'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_MATRIX(ch_input)
    GET_MATRIX.out.results.view { "Result: $it" }
}


workflow TEST_CREATE_SCVI_EMBEDDINGS_SCRNA {
    ch_input = Channel.of([
        [id: 'test_create_scvi_embeddings_scRNA'],
        file("${params.test_data}/placeholder.txt")
    ])
    CREATE_SCVI_EMBEDDINGS_SCRNA(ch_input)
    CREATE_SCVI_EMBEDDINGS_SCRNA.out.results.view { "Result: $it" }
}


workflow TEST_CONDA_ENV_EXISTS {
    ch_input = Channel.of([
        [id: 'test_conda_env_exists'],
        file("${params.test_data}/placeholder.txt")
    ])
    CONDA_ENV_EXISTS(ch_input)
    CONDA_ENV_EXISTS.out.results.view { "Result: $it" }
}


workflow TEST_MAP_TO_IMA_INTERPRET_SCRNA {
    ch_input = Channel.of([
        [id: 'test_map_to_ima_interpret_scRNA'],
        file("${params.test_data}/placeholder.txt")
    ])
    MAP_TO_IMA_INTERPRET_SCRNA(ch_input)
    MAP_TO_IMA_INTERPRET_SCRNA.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES {
    ch_input = Channel.of([
        [id: 'test_analyze_comparative_genomics_and_haplotypes'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES(ch_input)
    ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CHROMATIN_INTERACTIONS {
    ch_input = Channel.of([
        [id: 'test_analyze_chromatin_interactions'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CHROMATIN_INTERACTIONS(ch_input)
    ANALYZE_CHROMATIN_INTERACTIONS.out.results.view { "Result: $it" }
}


workflow TEST_GENERATE_TRANSCRIPTFORMER_EMBEDDINGS {
    ch_input = Channel.of([
        [id: 'test_generate_transcriptformer_embeddings'],
        file("${params.test_data}/placeholder.txt")
    ])
    GENERATE_TRANSCRIPTFORMER_EMBEDDINGS(ch_input)
    GENERATE_TRANSCRIPTFORMER_EMBEDDINGS.out.results.view { "Result: $it" }
}


workflow TEST_GENERATE_EMBEDDINGS_WITH_STATE {
    ch_input = Channel.of([
        [id: 'test_generate_embeddings_with_state'],
        file("${params.test_data}/placeholder.txt")
    ])
    GENERATE_EMBEDDINGS_WITH_STATE(ch_input)
    GENERATE_EMBEDDINGS_WITH_STATE.out.results.view { "Result: $it" }
}


workflow TEST_GET_RNA_SEQ_ARCHS4 {
    ch_input = Channel.of([
        [id: 'test_get_rna_seq_archs4'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_RNA_SEQ_ARCHS4(ch_input)
    GET_RNA_SEQ_ARCHS4.out.results.view { "Result: $it" }
}


workflow TEST_LIST_GLYCOENGINEERING_RESOURCES {
    ch_input = Channel.of([
        [id: 'test_list_glycoengineering_resources'],
        file("${params.test_data}/placeholder.txt")
    ])
    LIST_GLYCOENGINEERING_RESOURCES(ch_input)
    LIST_GLYCOENGINEERING_RESOURCES.out.results.view { "Result: $it" }
}


workflow TEST_FIND_N_GLYCOSYLATION_MOTIFS {
    ch_input = Channel.of([
        [id: 'test_find_n_glycosylation_motifs'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIND_N_GLYCOSYLATION_MOTIFS(ch_input)
    FIND_N_GLYCOSYLATION_MOTIFS.out.results.view { "Result: $it" }
}


workflow TEST_PREDICT_O_GLYCOSYLATION_HOTSPOTS {
    ch_input = Channel.of([
        [id: 'test_predict_o_glycosylation_hotspots'],
        file("${params.test_data}/placeholder.txt")
    ])
    PREDICT_O_GLYCOSYLATION_HOTSPOTS(ch_input)
    PREDICT_O_GLYCOSYLATION_HOTSPOTS.out.results.view { "Result: $it" }
}


workflow TEST_TRACK_IMMUNE_CELLS_UNDER_FLOW {
    ch_input = Channel.of([
        [id: 'test_track_immune_cells_under_flow'],
        file("${params.test_data}/placeholder.txt")
    ])
    TRACK_IMMUNE_CELLS_UNDER_FLOW(ch_input)
    TRACK_IMMUNE_CELLS_UNDER_FLOW.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS {
    ch_input = Channel.of([
        [id: 'test_analyze_cytokine_production_in_cd4_tcells'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS(ch_input)
    ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CFSE_CELL_PROLIFERATION {
    ch_input = Channel.of([
        [id: 'test_analyze_cfse_cell_proliferation'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CFSE_CELL_PROLIFERATION(ch_input)
    ANALYZE_CFSE_CELL_PROLIFERATION.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_CELL_POPULATION {
    ch_input = Channel.of([
        [id: 'test_simulate_cell_population'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_CELL_POPULATION(ch_input)
    SIMULATE_CELL_POPULATION.out.results.view { "Result: $it" }
}


workflow TEST_ESTIMATE_CELL_CYCLE_PHASE_DURATIONS {
    ch_input = Channel.of([
        [id: 'test_estimate_cell_cycle_phase_durations'],
        file("${params.test_data}/placeholder.txt")
    ])
    ESTIMATE_CELL_CYCLE_PHASE_DURATIONS(ch_input)
    ESTIMATE_CELL_CYCLE_PHASE_DURATIONS.out.results.view { "Result: $it" }
}


workflow TEST_ISOLATE_PURIFY_IMMUNE_CELLS {
    ch_input = Channel.of([
        [id: 'test_isolate_purify_immune_cells'],
        file("${params.test_data}/placeholder.txt")
    ])
    ISOLATE_PURIFY_IMMUNE_CELLS(ch_input)
    ISOLATE_PURIFY_IMMUNE_CELLS.out.results.view { "Result: $it" }
}


workflow TEST_LOGISTIC_GROWTH {
    ch_input = Channel.of([
        [id: 'test_logistic_growth'],
        file("${params.test_data}/placeholder.txt")
    ])
    LOGISTIC_GROWTH(ch_input)
    LOGISTIC_GROWTH.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE {
    ch_input = Channel.of([
        [id: 'test_analyze_immunohistochemistry_image'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE(ch_input)
    ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY {
    ch_input = Channel.of([
        [id: 'test_analyze_atac_seq_differential_accessibility'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY(ch_input)
    ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_EBV_ANTIBODY_TITERS {
    ch_input = Channel.of([
        [id: 'test_analyze_ebv_antibody_titers'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_EBV_ANTIBODY_TITERS(ch_input)
    ANALYZE_EBV_ANTIBODY_TITERS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_BACTERIAL_GROWTH_CURVE {
    ch_input = Channel.of([
        [id: 'test_analyze_bacterial_growth_curve'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_BACTERIAL_GROWTH_CURVE(ch_input)
    ANALYZE_BACTERIAL_GROWTH_CURVE.out.results.view { "Result: $it" }
}


workflow TEST_OBJECTIVE_FUNCTION {
    ch_input = Channel.of([
        [id: 'test_objective_function'],
        file("${params.test_data}/placeholder.txt")
    ])
    OBJECTIVE_FUNCTION(ch_input)
    OBJECTIVE_FUNCTION.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CNS_LESION_HISTOLOGY {
    ch_input = Channel.of([
        [id: 'test_analyze_cns_lesion_histology'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CNS_LESION_HISTOLOGY(ch_input)
    ANALYZE_CNS_LESION_HISTOLOGY.out.results.view { "Result: $it" }
}


workflow TEST_TARGET {
    ch_input = Channel.of([
        [id: 'test_target'],
        file("${params.test_data}/placeholder.txt")
    ])
    TARGET(ch_input)
    TARGET.out.results.view { "Result: $it" }
}


workflow TEST_GET_PYLABROBOT_DOCUMENTATION_LIQUID {
    ch_input = Channel.of([
        [id: 'test_get_pylabrobot_documentation_liquid'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_PYLABROBOT_DOCUMENTATION_LIQUID(ch_input)
    GET_PYLABROBOT_DOCUMENTATION_LIQUID.out.results.view { "Result: $it" }
}


workflow TEST_TEST_PYLABROBOT_SCRIPT {
    ch_input = Channel.of([
        [id: 'test_test_pylabrobot_script'],
        file("${params.test_data}/placeholder.txt")
    ])
    TEST_PYLABROBOT_SCRIPT(ch_input)
    TEST_PYLABROBOT_SCRIPT.out.results.view { "Result: $it" }
}


workflow TEST_PICK_FIRST {
    ch_input = Channel.of([
        [id: 'test_pick_first'],
        file("${params.test_data}/placeholder.txt")
    ])
    PICK_FIRST(ch_input)
    PICK_FIRST.out.results.view { "Result: $it" }
}


workflow TEST_RUN_ASYNC {
    ch_input = Channel.of([
        [id: 'test_run_async'],
        file("${params.test_data}/placeholder.txt")
    ])
    RUN_ASYNC(ch_input)
    RUN_ASYNC.out.results.view { "Result: $it" }
}


workflow TEST_GET_PYLABROBOT_DOCUMENTATION_MATERIAL {
    ch_input = Channel.of([
        [id: 'test_get_pylabrobot_documentation_material'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_PYLABROBOT_DOCUMENTATION_MATERIAL(ch_input)
    GET_PYLABROBOT_DOCUMENTATION_MATERIAL.out.results.view { "Result: $it" }
}


workflow TEST_FETCH_SUPPLEMENTARY_INFO_FROM_DOI {
    ch_input = Channel.of([
        [id: 'test_fetch_supplementary_info_from_doi'],
        file("${params.test_data}/placeholder.txt")
    ])
    FETCH_SUPPLEMENTARY_INFO_FROM_DOI(ch_input)
    FETCH_SUPPLEMENTARY_INFO_FROM_DOI.out.results.view { "Result: $it" }
}


workflow TEST_EXTRACT_URL_CONTENT {
    ch_input = Channel.of([
        [id: 'test_extract_url_content'],
        file("${params.test_data}/placeholder.txt")
    ])
    EXTRACT_URL_CONTENT(ch_input)
    EXTRACT_URL_CONTENT.out.results.view { "Result: $it" }
}


workflow TEST_ADVANCED_WEB_SEARCH_CLAUDE {
    ch_input = Channel.of([
        [id: 'test_advanced_web_search_claude'],
        file("${params.test_data}/placeholder.txt")
    ])
    ADVANCED_WEB_SEARCH_CLAUDE(ch_input)
    ADVANCED_WEB_SEARCH_CLAUDE.out.results.view { "Result: $it" }
}


workflow TEST_EXTRACT_PDF_CONTENT {
    ch_input = Channel.of([
        [id: 'test_extract_pdf_content'],
        file("${params.test_data}/placeholder.txt")
    ])
    EXTRACT_PDF_CONTENT(ch_input)
    EXTRACT_PDF_CONTENT.out.results.view { "Result: $it" }
}


workflow TEST_MODEL_BACTERIAL_GROWTH_DYNAMICS {
    ch_input = Channel.of([
        [id: 'test_model_bacterial_growth_dynamics'],
        file("${params.test_data}/placeholder.txt")
    ])
    MODEL_BACTERIAL_GROWTH_DYNAMICS(ch_input)
    MODEL_BACTERIAL_GROWTH_DYNAMICS.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS {
    ch_input = Channel.of([
        [id: 'test_simulate_generalized_lotka_volterra_dynamics'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS(ch_input)
    SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS.out.results.view { "Result: $it" }
}


workflow TEST_QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET {
    ch_input = Channel.of([
        [id: 'test_quantify_biofilm_biomass_crystal_violet'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET(ch_input)
    QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET.out.results.view { "Result: $it" }
}


workflow TEST_COUNT_BACTERIAL_COLONIES {
    ch_input = Channel.of([
        [id: 'test_count_bacterial_colonies'],
        file("${params.test_data}/placeholder.txt")
    ])
    COUNT_BACTERIAL_COLONIES(ch_input)
    COUNT_BACTERIAL_COLONIES.out.results.view { "Result: $it" }
}


workflow TEST_ANNOTATE_BACTERIAL_GENOME {
    ch_input = Channel.of([
        [id: 'test_annotate_bacterial_genome'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANNOTATE_BACTERIAL_GENOME(ch_input)
    ANNOTATE_BACTERIAL_GENOME.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_MICROBIAL_POPULATION_DYNAMICS {
    ch_input = Channel.of([
        [id: 'test_simulate_microbial_population_dynamics'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_MICROBIAL_POPULATION_DYNAMICS(ch_input)
    SIMULATE_MICROBIAL_POPULATION_DYNAMICS.out.results.view { "Result: $it" }
}


workflow TEST_VFA_PRODUCTION_MODEL {
    ch_input = Channel.of([
        [id: 'test_vfa_production_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    VFA_PRODUCTION_MODEL(ch_input)
    VFA_PRODUCTION_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_PREDICT_RNA_SECONDARY_STRUCTURE {
    ch_input = Channel.of([
        [id: 'test_predict_rna_secondary_structure'],
        file("${params.test_data}/placeholder.txt")
    ])
    PREDICT_RNA_SECONDARY_STRUCTURE(ch_input)
    PREDICT_RNA_SECONDARY_STRUCTURE.out.results.view { "Result: $it" }
}


workflow TEST_ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION {
    ch_input = Channel.of([
        [id: 'test_enumerate_bacterial_cfu_by_serial_dilution'],
        file("${params.test_data}/placeholder.txt")
    ])
    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION(ch_input)
    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.results.view { "Result: $it" }
}


workflow TEST_SEGMENT_AND_ANALYZE_MICROBIAL_CELLS {
    ch_input = Channel.of([
        [id: 'test_segment_and_analyze_microbial_cells'],
        file("${params.test_data}/placeholder.txt")
    ])
    SEGMENT_AND_ANALYZE_MICROBIAL_CELLS(ch_input)
    SEGMENT_AND_ANALYZE_MICROBIAL_CELLS.out.results.view { "Result: $it" }
}


workflow TEST_BACTERIAL_DYNAMICS {
    ch_input = Channel.of([
        [id: 'test_bacterial_dynamics'],
        file("${params.test_data}/placeholder.txt")
    ])
    BACTERIAL_DYNAMICS(ch_input)
    BACTERIAL_DYNAMICS.out.results.view { "Result: $it" }
}


workflow TEST_METHANE_YIELD_MODEL {
    ch_input = Channel.of([
        [id: 'test_methane_yield_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    METHANE_YIELD_MODEL(ch_input)
    METHANE_YIELD_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_SEGMENT_CELLS_WITH_DEEP_LEARNING {
    ch_input = Channel.of([
        [id: 'test_segment_cells_with_deep_learning'],
        file("${params.test_data}/placeholder.txt")
    ])
    SEGMENT_CELLS_WITH_DEEP_LEARNING(ch_input)
    SEGMENT_CELLS_WITH_DEEP_LEARNING.out.results.view { "Result: $it" }
}


workflow TEST_GLV_EQUATIONS {
    ch_input = Channel.of([
        [id: 'test_glv_equations'],
        file("${params.test_data}/placeholder.txt")
    ])
    GLV_EQUATIONS(ch_input)
    GLV_EQUATIONS.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS {
    ch_input = Channel.of([
        [id: 'test_analyze_arsenic_speciation_hplc_icpms'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS(ch_input)
    ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS.out.results.view { "Result: $it" }
}


workflow TEST_OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS {
    ch_input = Channel.of([
        [id: 'test_optimize_anaerobic_digestion_process'],
        file("${params.test_data}/placeholder.txt")
    ])
    OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS(ch_input)
    OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS.out.results.view { "Result: $it" }
}


workflow TEST_FIND_SEQUENCE_MUTATIONS {
    ch_input = Channel.of([
        [id: 'test_find_sequence_mutations'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIND_SEQUENCE_MUTATIONS(ch_input)
    FIND_SEQUENCE_MUTATIONS.out.results.view { "Result: $it" }
}


workflow TEST_FIND_RESTRICTION_ENZYMES {
    ch_input = Channel.of([
        [id: 'test_find_restriction_enzymes'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIND_RESTRICTION_ENZYMES(ch_input)
    FIND_RESTRICTION_ENZYMES.out.results.view { "Result: $it" }
}


workflow TEST_ANNOTATE_OPEN_READING_FRAMES {
    ch_input = Channel.of([
        [id: 'test_annotate_open_reading_frames'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANNOTATE_OPEN_READING_FRAMES(ch_input)
    ANNOTATE_OPEN_READING_FRAMES.out.results.view { "Result: $it" }
}


workflow TEST_DESIGN_GOLDEN_GATE_OLIGOS {
    ch_input = Channel.of([
        [id: 'test_design_golden_gate_oligos'],
        file("${params.test_data}/placeholder.txt")
    ])
    DESIGN_GOLDEN_GATE_OLIGOS(ch_input)
    DESIGN_GOLDEN_GATE_OLIGOS.out.results.view { "Result: $it" }
}


workflow TEST_DESIGN_VERIFICATION_PRIMERS {
    ch_input = Channel.of([
        [id: 'test_design_verification_primers'],
        file("${params.test_data}/placeholder.txt")
    ])
    DESIGN_VERIFICATION_PRIMERS(ch_input)
    DESIGN_VERIFICATION_PRIMERS.out.results.view { "Result: $it" }
}


workflow TEST_GOLDEN_GATE_ASSEMBLY {
    ch_input = Channel.of([
        [id: 'test_golden_gate_assembly'],
        file("${params.test_data}/placeholder.txt")
    ])
    GOLDEN_GATE_ASSEMBLY(ch_input)
    GOLDEN_GATE_ASSEMBLY.out.results.view { "Result: $it" }
}


workflow TEST_GET_REFSEQ_ID {
    ch_input = Channel.of([
        [id: 'test_get_refseq_id'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_REFSEQ_ID(ch_input)
    GET_REFSEQ_ID.out.results.view { "Result: $it" }
}


workflow TEST_GET_GENE_CODING_SEQUENCE {
    ch_input = Channel.of([
        [id: 'test_get_gene_coding_sequence'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_GENE_CODING_SEQUENCE(ch_input)
    GET_GENE_CODING_SEQUENCE.out.results.view { "Result: $it" }
}


workflow TEST_PCR_SIMPLE {
    ch_input = Channel.of([
        [id: 'test_pcr_simple'],
        file("${params.test_data}/placeholder.txt")
    ])
    PCR_SIMPLE(ch_input)
    PCR_SIMPLE.out.results.view { "Result: $it" }
}


workflow TEST_IS_POSITION_COVERED {
    ch_input = Channel.of([
        [id: 'test_is_position_covered'],
        file("${params.test_data}/placeholder.txt")
    ])
    IS_POSITION_COVERED(ch_input)
    IS_POSITION_COVERED.out.results.view { "Result: $it" }
}


workflow TEST_GET_CODING_SEQUENCES {
    ch_input = Channel.of([
        [id: 'test_get_coding_sequences'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_CODING_SEQUENCES(ch_input)
    GET_CODING_SEQUENCES.out.results.view { "Result: $it" }
}


workflow TEST_REVERSE_COMPLEMENT {
    ch_input = Channel.of([
        [id: 'test_reverse_complement'],
        file("${params.test_data}/placeholder.txt")
    ])
    REVERSE_COMPLEMENT(ch_input)
    REVERSE_COMPLEMENT.out.results.view { "Result: $it" }
}


workflow TEST_FIND_RESTRICTION_SITES {
    ch_input = Channel.of([
        [id: 'test_find_restriction_sites'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIND_RESTRICTION_SITES(ch_input)
    FIND_RESTRICTION_SITES.out.results.view { "Result: $it" }
}


workflow TEST_FIND_ORFS_IN_FRAME {
    ch_input = Channel.of([
        [id: 'test_find_orfs_in_frame'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIND_ORFS_IN_FRAME(ch_input)
    FIND_ORFS_IN_FRAME.out.results.view { "Result: $it" }
}


workflow TEST_ALIGN_SEQUENCES {
    ch_input = Channel.of([
        [id: 'test_align_sequences'],
        file("${params.test_data}/placeholder.txt")
    ])
    ALIGN_SEQUENCES(ch_input)
    ALIGN_SEQUENCES.out.results.view { "Result: $it" }
}


workflow TEST_GET_PLASMID_SEQUENCE {
    ch_input = Channel.of([
        [id: 'test_get_plasmid_sequence'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_PLASMID_SEQUENCE(ch_input)
    GET_PLASMID_SEQUENCE.out.results.view { "Result: $it" }
}


workflow TEST_GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL {
    ch_input = Channel.of([
        [id: 'test_get_golden_gate_assembly_protocol'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL(ch_input)
    GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL.out.results.view { "Result: $it" }
}


workflow TEST_MERGE_OVERLAPPING_REGIONS {
    ch_input = Channel.of([
        [id: 'test_merge_overlapping_regions'],
        file("${params.test_data}/placeholder.txt")
    ])
    MERGE_OVERLAPPING_REGIONS(ch_input)
    MERGE_OVERLAPPING_REGIONS.out.results.view { "Result: $it" }
}


workflow TEST_DESIGN_KNOCKOUT_SGRNA {
    ch_input = Channel.of([
        [id: 'test_design_knockout_sgrna'],
        file("${params.test_data}/placeholder.txt")
    ])
    DESIGN_KNOCKOUT_SGRNA(ch_input)
    DESIGN_KNOCKOUT_SGRNA.out.results.view { "Result: $it" }
}


workflow TEST_GET_OLIGO_ANNEALING_PROTOCOL {
    ch_input = Channel.of([
        [id: 'test_get_oligo_annealing_protocol'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_OLIGO_ANNEALING_PROTOCOL(ch_input)
    GET_OLIGO_ANNEALING_PROTOCOL.out.results.view { "Result: $it" }
}


workflow TEST_GET_BACTERIAL_TRANSFORMATION_PROTOCOL {
    ch_input = Channel.of([
        [id: 'test_get_bacterial_transformation_protocol'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_BACTERIAL_TRANSFORMATION_PROTOCOL(ch_input)
    GET_BACTERIAL_TRANSFORMATION_PROTOCOL.out.results.view { "Result: $it" }
}


workflow TEST_DIGEST_SEQUENCE {
    ch_input = Channel.of([
        [id: 'test_digest_sequence'],
        file("${params.test_data}/placeholder.txt")
    ])
    DIGEST_SEQUENCE(ch_input)
    DIGEST_SEQUENCE.out.results.view { "Result: $it" }
}


workflow TEST_ANNOTATE_PLASMID {
    ch_input = Channel.of([
        [id: 'test_annotate_plasmid'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANNOTATE_PLASMID(ch_input)
    ANNOTATE_PLASMID.out.results.view { "Result: $it" }
}


workflow TEST_IS_REGION_FULLY_COVERED {
    ch_input = Channel.of([
        [id: 'test_is_region_fully_covered'],
        file("${params.test_data}/placeholder.txt")
    ])
    IS_REGION_FULLY_COVERED(ch_input)
    IS_REGION_FULLY_COVERED.out.results.view { "Result: $it" }
}


workflow TEST_DESIGN_PRIMER {
    ch_input = Channel.of([
        [id: 'test_design_primer'],
        file("${params.test_data}/placeholder.txt")
    ])
    DESIGN_PRIMER(ch_input)
    DESIGN_PRIMER.out.results.view { "Result: $it" }
}


workflow TEST_SEARCH_GENE {
    ch_input = Channel.of([
        [id: 'test_search_gene'],
        file("${params.test_data}/placeholder.txt")
    ])
    SEARCH_GENE(ch_input)
    SEARCH_GENE.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY {
    ch_input = Channel.of([
        [id: 'test_analyze_aortic_diameter_and_geometry'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY(ch_input)
    ANALYZE_AORTIC_DIAMETER_AND_GEOMETRY.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2 {
    ch_input = Channel.of([
        [id: 'test_analyze_intracellular_calcium_with_rhod2'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2(ch_input)
    ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_THROMBUS_HISTOLOGY {
    ch_input = Channel.of([
        [id: 'test_analyze_thrombus_histology'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_THROMBUS_HISTOLOGY(ch_input)
    ANALYZE_THROMBUS_HISTOLOGY.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_ATP_LUMINESCENCE_ASSAY {
    ch_input = Channel.of([
        [id: 'test_analyze_atp_luminescence_assay'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_ATP_LUMINESCENCE_ASSAY(ch_input)
    ANALYZE_ATP_LUMINESCENCE_ASSAY.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_BONE_MICROCT_MORPHOMETRY {
    ch_input = Channel.of([
        [id: 'test_analyze_bone_microct_morphometry'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_BONE_MICROCT_MORPHOMETRY(ch_input)
    ANALYZE_BONE_MICROCT_MORPHOMETRY.out.results.view { "Result: $it" }
}


workflow TEST_QUANTIFY_CORNEAL_NERVE_FIBERS {
    ch_input = Channel.of([
        [id: 'test_quantify_corneal_nerve_fibers'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUANTIFY_CORNEAL_NERVE_FIBERS(ch_input)
    QUANTIFY_CORNEAL_NERVE_FIBERS.out.results.view { "Result: $it" }
}


workflow TEST_SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES {
    ch_input = Channel.of([
        [id: 'test_segment_and_quantify_cells_in_multiplexed_images'],
        file("${params.test_data}/placeholder.txt")
    ])
    SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES(ch_input)
    SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION {
    ch_input = Channel.of([
        [id: 'test_analyze_radiolabeled_antibody_biodistribution'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION(ch_input)
    ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_WESTERN_BLOT {
    ch_input = Channel.of([
        [id: 'test_analyze_western_blot'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_WESTERN_BLOT(ch_input)
    ANALYZE_WESTERN_BLOT.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS {
    ch_input = Channel.of([
        [id: 'test_analyze_accelerated_stability_of_pharmaceutical_formulations'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS(ch_input)
    ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS.out.results.view { "Result: $it" }
}


workflow TEST_ADMET_PRED {
    ch_input = Channel.of([
        [id: 'test_ADMET_pred'],
        file("${params.test_data}/placeholder.txt")
    ])
    ADMET_PRED(ch_input)
    ADMET_PRED.out.results.view { "Result: $it" }
}


workflow TEST_RUN_DIFFDOCK_WITH_SMILES {
    ch_input = Channel.of([
        [id: 'test_run_diffdock_with_smiles'],
        file("${params.test_data}/placeholder.txt")
    ])
    RUN_DIFFDOCK_WITH_SMILES(ch_input)
    RUN_DIFFDOCK_WITH_SMILES.out.results.view { "Result: $it" }
}


workflow TEST_CALCULATE_PHYSICOCHEMICAL_PROPERTIES {
    ch_input = Channel.of([
        [id: 'test_calculate_physicochemical_properties'],
        file("${params.test_data}/placeholder.txt")
    ])
    CALCULATE_PHYSICOCHEMICAL_PROPERTIES(ch_input)
    CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_FDA_SAFETY_SIGNALS {
    ch_input = Channel.of([
        [id: 'test_analyze_fda_safety_signals'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_FDA_SAFETY_SIGNALS(ch_input)
    ANALYZE_FDA_SAFETY_SIGNALS.out.results.view { "Result: $it" }
}


workflow TEST_RUN_AUTOSITE {
    ch_input = Channel.of([
        [id: 'test_run_autosite'],
        file("${params.test_data}/placeholder.txt")
    ])
    RUN_AUTOSITE(ch_input)
    RUN_AUTOSITE.out.results.view { "Result: $it" }
}


workflow TEST_GET_FDA_DRUG_LABEL_INFO {
    ch_input = Channel.of([
        [id: 'test_get_fda_drug_label_info'],
        file("${params.test_data}/placeholder.txt")
    ])
    GET_FDA_DRUG_LABEL_INFO(ch_input)
    GET_FDA_DRUG_LABEL_INFO.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_INTERACTION_MECHANISMS {
    ch_input = Channel.of([
        [id: 'test_analyze_interaction_mechanisms'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_INTERACTION_MECHANISMS(ch_input)
    ANALYZE_INTERACTION_MECHANISMS.out.results.view { "Result: $it" }
}


workflow TEST_ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY {
    ch_input = Channel.of([
        [id: 'test_estimate_alpha_particle_radiotherapy_dosimetry'],
        file("${params.test_data}/placeholder.txt")
    ])
    ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY(ch_input)
    ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION {
    ch_input = Channel.of([
        [id: 'test_analyze_xenograft_tumor_growth_inhibition'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION(ch_input)
    ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION.out.results.view { "Result: $it" }
}


workflow TEST_PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE {
    ch_input = Channel.of([
        [id: 'test_predict_binding_affinity_protein_1d_sequence'],
        file("${params.test_data}/placeholder.txt")
    ])
    PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE(ch_input)
    PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE.out.results.view { "Result: $it" }
}


workflow TEST_DOCKING_AUTODOCK_VINA {
    ch_input = Channel.of([
        [id: 'test_docking_autodock_vina'],
        file("${params.test_data}/placeholder.txt")
    ])
    DOCKING_AUTODOCK_VINA(ch_input)
    DOCKING_AUTODOCK_VINA.out.results.view { "Result: $it" }
}


workflow TEST_CHECK_FDA_DRUG_RECALLS {
    ch_input = Channel.of([
        [id: 'test_check_fda_drug_recalls'],
        file("${params.test_data}/placeholder.txt")
    ])
    CHECK_FDA_DRUG_RECALLS(ch_input)
    CHECK_FDA_DRUG_RECALLS.out.results.view { "Result: $it" }
}


workflow TEST_CHECK_DRUG_COMBINATION_SAFETY {
    ch_input = Channel.of([
        [id: 'test_check_drug_combination_safety'],
        file("${params.test_data}/placeholder.txt")
    ])
    CHECK_DRUG_COMBINATION_SAFETY(ch_input)
    CHECK_DRUG_COMBINATION_SAFETY.out.results.view { "Result: $it" }
}


workflow TEST_APPLY_VCOG_GRADE {
    ch_input = Channel.of([
        [id: 'test_apply_vcog_grade'],
        file("${params.test_data}/placeholder.txt")
    ])
    APPLY_VCOG_GRADE(ch_input)
    APPLY_VCOG_GRADE.out.results.view { "Result: $it" }
}


workflow TEST_RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY {
    ch_input = Channel.of([
        [id: 'test_run_3d_chondrogenic_aggregate_assay'],
        file("${params.test_data}/placeholder.txt")
    ])
    RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY(ch_input)
    RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY.out.results.view { "Result: $it" }
}


workflow TEST_SIGMOID {
    ch_input = Channel.of([
        [id: 'test_sigmoid'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIGMOID(ch_input)
    SIGMOID.out.results.view { "Result: $it" }
}


workflow TEST_BI_EXP_MODEL {
    ch_input = Channel.of([
        [id: 'test_bi_exp_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    BI_EXP_MODEL(ch_input)
    BI_EXP_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS {
    ch_input = Channel.of([
        [id: 'test_perform_mwas_cyp2c19_metabolizer_status'],
        file("${params.test_data}/placeholder.txt")
    ])
    PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS(ch_input)
    PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS.out.results.view { "Result: $it" }
}


workflow TEST_RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN {
    ch_input = Channel.of([
        [id: 'test_retrieve_topk_repurposing_drugs_from_disease_txgnn'],
        file("${params.test_data}/placeholder.txt")
    ])
    RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN(ch_input)
    RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN.out.results.view { "Result: $it" }
}


workflow TEST_FIND_ALTERNATIVE_DRUGS_DDINTER {
    ch_input = Channel.of([
        [id: 'test_find_alternative_drugs_ddinter'],
        file("${params.test_data}/placeholder.txt")
    ])
    FIND_ALTERNATIVE_DRUGS_DDINTER(ch_input)
    FIND_ALTERNATIVE_DRUGS_DDINTER.out.results.view { "Result: $it" }
}


workflow TEST_PREDICT_ADMET_PROPERTIES {
    ch_input = Channel.of([
        [id: 'test_predict_admet_properties'],
        file("${params.test_data}/placeholder.txt")
    ])
    PREDICT_ADMET_PROPERTIES(ch_input)
    PREDICT_ADMET_PROPERTIES.out.results.view { "Result: $it" }
}


workflow TEST_GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE {
    ch_input = Channel.of([
        [id: 'test_grade_adverse_events_using_vcog_ctcae'],
        file("${params.test_data}/placeholder.txt")
    ])
    GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE(ch_input)
    GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_FATTY_ACID_COMPOSITION_BY_GC {
    ch_input = Channel.of([
        [id: 'test_analyze_fatty_acid_composition_by_gc'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_FATTY_ACID_COMPOSITION_BY_GC(ch_input)
    ANALYZE_FATTY_ACID_COMPOSITION_BY_GC.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_CILIARY_BEAT_FREQUENCY {
    ch_input = Channel.of([
        [id: 'test_analyze_ciliary_beat_frequency'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_CILIARY_BEAT_FREQUENCY(ch_input)
    ANALYZE_CILIARY_BEAT_FREQUENCY.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_ABR_WAVEFORM_P1_METRICS {
    ch_input = Channel.of([
        [id: 'test_analyze_abr_waveform_p1_metrics'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_ABR_WAVEFORM_P1_METRICS(ch_input)
    ANALYZE_ABR_WAVEFORM_P1_METRICS.out.results.view { "Result: $it" }
}


workflow TEST_CALCULATE_BRAIN_ADC_MAP {
    ch_input = Channel.of([
        [id: 'test_calculate_brain_adc_map'],
        file("${params.test_data}/placeholder.txt")
    ])
    CALCULATE_BRAIN_ADC_MAP(ch_input)
    CALCULATE_BRAIN_ADC_MAP.out.results.view { "Result: $it" }
}


workflow TEST_MONO_EXP_MODEL {
    ch_input = Channel.of([
        [id: 'test_mono_exp_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    MONO_EXP_MODEL(ch_input)
    MONO_EXP_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_HEMODYNAMIC_DATA {
    ch_input = Channel.of([
        [id: 'test_analyze_hemodynamic_data'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_HEMODYNAMIC_DATA(ch_input)
    ANALYZE_HEMODYNAMIC_DATA.out.results.view { "Result: $it" }
}


workflow TEST_PERFORM_COSINOR_ANALYSIS {
    ch_input = Channel.of([
        [id: 'test_perform_cosinor_analysis'],
        file("${params.test_data}/placeholder.txt")
    ])
    PERFORM_COSINOR_ANALYSIS(ch_input)
    PERFORM_COSINOR_ANALYSIS.out.results.view { "Result: $it" }
}


workflow TEST_PK_ODE_SYSTEM {
    ch_input = Channel.of([
        [id: 'test_pk_ode_system'],
        file("${params.test_data}/placeholder.txt")
    ])
    PK_ODE_SYSTEM(ch_input)
    PK_ODE_SYSTEM.out.results.view { "Result: $it" }
}


workflow TEST_RECONSTRUCT_3D_FACE_FROM_MRI {
    ch_input = Channel.of([
        [id: 'test_reconstruct_3d_face_from_mri'],
        file("${params.test_data}/placeholder.txt")
    ])
    RECONSTRUCT_3D_FACE_FROM_MRI(ch_input)
    RECONSTRUCT_3D_FACE_FROM_MRI.out.results.view { "Result: $it" }
}


workflow TEST_COSINOR_MODEL {
    ch_input = Channel.of([
        [id: 'test_cosinor_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    COSINOR_MODEL(ch_input)
    COSINOR_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_PROTEIN_COLOCALIZATION {
    ch_input = Channel.of([
        [id: 'test_analyze_protein_colocalization'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_PROTEIN_COLOCALIZATION(ch_input)
    ANALYZE_PROTEIN_COLOCALIZATION.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_THYROID_HORMONE_PHARMACOKINETICS {
    ch_input = Channel.of([
        [id: 'test_simulate_thyroid_hormone_pharmacokinetics'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_THYROID_HORMONE_PHARMACOKINETICS(ch_input)
    SIMULATE_THYROID_HORMONE_PHARMACOKINETICS.out.results.view { "Result: $it" }
}


workflow TEST_QUANTIFY_AMYLOID_BETA_PLAQUES {
    ch_input = Channel.of([
        [id: 'test_quantify_amyloid_beta_plaques'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUANTIFY_AMYLOID_BETA_PLAQUES(ch_input)
    QUANTIFY_AMYLOID_BETA_PLAQUES.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS {
    ch_input = Channel.of([
        [id: 'test_analyze_endolysosomal_calcium_dynamics'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS(ch_input)
    ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK {
    ch_input = Channel.of([
        [id: 'test_simulate_gene_circuit_with_growth_feedback'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK(ch_input)
    SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK.out.results.view { "Result: $it" }
}


workflow TEST_GOMPERTZ_MODEL {
    ch_input = Channel.of([
        [id: 'test_gompertz_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    GOMPERTZ_MODEL(ch_input)
    GOMPERTZ_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_BACTERIAL_GROWTH_RATE {
    ch_input = Channel.of([
        [id: 'test_analyze_bacterial_growth_rate'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_BACTERIAL_GROWTH_RATE(ch_input)
    ANALYZE_BACTERIAL_GROWTH_RATE.out.results.view { "Result: $it" }
}


workflow TEST_CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL {
    ch_input = Channel.of([
        [id: 'test_create_biochemical_network_sbml_model'],
        file("${params.test_data}/placeholder.txt")
    ])
    CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL(ch_input)
    CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL.out.results.view { "Result: $it" }
}


workflow TEST_ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY {
    ch_input = Channel.of([
        [id: 'test_engineer_bacterial_genome_for_therapeutic_delivery'],
        file("${params.test_data}/placeholder.txt")
    ])
    ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY(ch_input)
    ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY.out.results.view { "Result: $it" }
}


workflow TEST_GENE_CIRCUIT_ODES {
    ch_input = Channel.of([
        [id: 'test_gene_circuit_odes'],
        file("${params.test_data}/placeholder.txt")
    ])
    GENE_CIRCUIT_ODES(ch_input)
    GENE_CIRCUIT_ODES.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_BIFURCATION_DIAGRAM {
    ch_input = Channel.of([
        [id: 'test_analyze_bifurcation_diagram'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_BIFURCATION_DIAGRAM(ch_input)
    ANALYZE_BIFURCATION_DIAGRAM.out.results.view { "Result: $it" }
}


workflow TEST_IDENTIFY_FAS_FUNCTIONAL_DOMAINS {
    ch_input = Channel.of([
        [id: 'test_identify_fas_functional_domains'],
        file("${params.test_data}/placeholder.txt")
    ])
    IDENTIFY_FAS_FUNCTIONAL_DOMAINS(ch_input)
    IDENTIFY_FAS_FUNCTIONAL_DOMAINS.out.results.view { "Result: $it" }
}


workflow TEST_HAMMING_DISTANCE {
    ch_input = Channel.of([
        [id: 'test_hamming_distance'],
        file("${params.test_data}/placeholder.txt")
    ])
    HAMMING_DISTANCE(ch_input)
    HAMMING_DISTANCE.out.results.view { "Result: $it" }
}


workflow TEST_ANALYZE_BARCODE_SEQUENCING_DATA {
    ch_input = Channel.of([
        [id: 'test_analyze_barcode_sequencing_data'],
        file("${params.test_data}/placeholder.txt")
    ])
    ANALYZE_BARCODE_SEQUENCING_DATA(ch_input)
    ANALYZE_BARCODE_SEQUENCING_DATA.out.results.view { "Result: $it" }
}


workflow TEST_OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION {
    ch_input = Channel.of([
        [id: 'test_optimize_codons_for_heterologous_expression'],
        file("${params.test_data}/placeholder.txt")
    ])
    OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION(ch_input)
    OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_PROTEIN_SIGNALING_NETWORK {
    ch_input = Channel.of([
        [id: 'test_simulate_protein_signaling_network'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_PROTEIN_SIGNALING_NETWORK(ch_input)
    SIMULATE_PROTEIN_SIGNALING_NETWORK.out.results.view { "Result: $it" }
}


workflow TEST_RAS_ODE_SYSTEM {
    ch_input = Channel.of([
        [id: 'test_ras_ode_system'],
        file("${params.test_data}/placeholder.txt")
    ])
    RAS_ODE_SYSTEM(ch_input)
    RAS_ODE_SYSTEM.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS {
    ch_input = Channel.of([
        [id: 'test_simulate_renin_angiotensin_system_dynamics'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS(ch_input)
    SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS.out.results.view { "Result: $it" }
}


workflow TEST_ODE_SYSTEM {
    ch_input = Channel.of([
        [id: 'test_ode_system'],
        file("${params.test_data}/placeholder.txt")
    ])
    ODE_SYSTEM(ch_input)
    ODE_SYSTEM.out.results.view { "Result: $it" }
}


workflow TEST_SIMULATE_METABOLIC_NETWORK_PERTURBATION {
    ch_input = Channel.of([
        [id: 'test_simulate_metabolic_network_perturbation'],
        file("${params.test_data}/placeholder.txt")
    ])
    SIMULATE_METABOLIC_NETWORK_PERTURBATION(ch_input)
    SIMULATE_METABOLIC_NETWORK_PERTURBATION.out.results.view { "Result: $it" }
}


workflow TEST_COMPARE_PROTEIN_STRUCTURES {
    ch_input = Channel.of([
        [id: 'test_compare_protein_structures'],
        file("${params.test_data}/placeholder.txt")
    ])
    COMPARE_PROTEIN_STRUCTURES(ch_input)
    COMPARE_PROTEIN_STRUCTURES.out.results.view { "Result: $it" }
}


workflow TEST_PERFORM_FLUX_BALANCE_ANALYSIS {
    ch_input = Channel.of([
        [id: 'test_perform_flux_balance_analysis'],
        file("${params.test_data}/placeholder.txt")
    ])
    PERFORM_FLUX_BALANCE_ANALYSIS(ch_input)
    PERFORM_FLUX_BALANCE_ANALYSIS.out.results.view { "Result: $it" }
}


workflow TEST_MASS_ACTION_KINETICS {
    ch_input = Channel.of([
        [id: 'test_mass_action_kinetics'],
        file("${params.test_data}/placeholder.txt")
    ])
    MASS_ACTION_KINETICS(ch_input)
    MASS_ACTION_KINETICS.out.results.view { "Result: $it" }
}


workflow TEST_MODEL_PROTEIN_DIMERIZATION_NETWORK {
    ch_input = Channel.of([
        [id: 'test_model_protein_dimerization_network'],
        file("${params.test_data}/placeholder.txt")
    ])
    MODEL_PROTEIN_DIMERIZATION_NETWORK(ch_input)
    MODEL_PROTEIN_DIMERIZATION_NETWORK.out.results.view { "Result: $it" }
}


workflow TEST_HILL_FUNCTION {
    ch_input = Channel.of([
        [id: 'test_hill_function'],
        file("${params.test_data}/placeholder.txt")
    ])
    HILL_FUNCTION(ch_input)
    HILL_FUNCTION.out.results.view { "Result: $it" }
}


workflow TEST_DIMERIZATION_ODES {
    ch_input = Channel.of([
        [id: 'test_dimerization_odes'],
        file("${params.test_data}/placeholder.txt")
    ])
    DIMERIZATION_ODES(ch_input)
    DIMERIZATION_ODES.out.results.view { "Result: $it" }
}


workflow TEST_QUERY_CHATNT {
    ch_input = Channel.of([
        [id: 'test_query_chatnt'],
        file("${params.test_data}/placeholder.txt")
    ])
    QUERY_CHATNT(ch_input)
    QUERY_CHATNT.out.results.view { "Result: $it" }
}


workflow {
    // Run tests based on params.test
    println "Running Biomni tool tests..."
}
