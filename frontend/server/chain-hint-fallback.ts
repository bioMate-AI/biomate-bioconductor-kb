/**
 * Fallback list of `chain_hint` names used by the intent classifier when the
 * Galaxy `/api/workflow-chains` endpoint is unreachable at boot.
 *
 * MUST stay in sync with `workflow_chains` rows where `source != 'bioc_reactive'`
 * (see `backend/scripts/index_all_workflows.py` CURATED_CHAINS).
 *
 * Drift here silently degrades Tier-2 chain routing — the classifier only
 * proposes chains it knows about. Guarded by `chain-hint-fallback.test.ts`.
 *
 * Proposal context: docs/20260607_PARALLELISM_AND_CROSS_DOMAIN_CHAINING_PROPOSAL.md (C7).
 *
 * Kept in its own module so the unit test can import the constant without
 * pulling in galaxy-assistant.ts's transitive DB dependencies.
 */

export const CHAIN_HINT_FALLBACK: readonly string[] = [
  'admet_to_cipa_cardiac',
  'admet_to_virtual_patient_dose_opt',
  'alternative_polyadenylation_analysis',
  'andv_inhibitor_track_v1',
  'bioc_variant_annotation_workflow',
  'bp4_rnaseq_best_practices_pipeline',
  'bulk_rnaseq_de_analysis',
  'cage_seq_promoter_analysis',
  'chipseq_window_based_differential_binding',
  'cutandtag_chromatin_analysis',
  'cytof_mass_cytometry_analysis',
  'drug_discovery_admet_gated_screening',
  'drug_discovery_screening',
  'ensemble_gene_set_enrichment_egsea',
  'genome_coordinate_liftover',
  'geomx_spatial_transcriptomics',
  'mageck_to_gears_moa',
  'methylation_450k_array_analysis',
  'microarray_normalization_comparison',
  'multiomic_differential_expression_exphunter',
  'pbpk_to_tumor_tgi',
  'rare_disease_multimodal_workup',
  'recount_public_rnaseq_reanalysis',
  'rnaseq_differential_transcript_usage',
  'rnaseq_epigenomic_integration_fluent',
  'rnaseq_to_lincs_moa',
  'single_cell_multimodal_analysis',
  'small_rna_piRNA_seqpac_analysis',
  'target_to_lead_full',
];
