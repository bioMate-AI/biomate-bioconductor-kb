# Workflow Test Status

Last updated: 2026-01-28

## Summary
- **Total modules**: 235 (2 archived due to broken external APIs)
- **Passed with proper test data**: ~210+
- **Needs external files**: ~25 (FCS, complex images, BAM files)
- **Docker/library issues**: ~5 (most packages now installed)
- **Parameter fixes needed**: 0 (all fixed)

## Recent Fixes (2026-01-28)
- Added pylabrobot and nnunetv2 packages to biomni-tools Docker container
- Created nextflow.config symlinks in all 235 workflow directories for proper Docker profile loading
- Fixed molecular_biology/pcr_simple parameter names (sequence, forward_primer, reverse_primer)
- Fixed molecular_biology/design_golden_gate_oligos with BsaI enzyme and proper sequences
- Fixed molecular_biology/golden_gate_assembly with proper fragment oligos
- Added test script to lab_automation/test_pylabrobot_script
- Fixed database workflow test parameters (get_genes_near_ccre, blast_sequence, get_hpo_names, reduce_tokens, region_to_ccre_screen)

## Archived Workflows (Broken External APIs)
Moved to `../archived_workflows_broken_api/`:
- biophysics/predict_protein_disorder_regions - IUPred2A API returns 404
- synthetic_biology/identify_fas_functional_domains - HMMER API returns 405

## Recently Fixed Workflows (with proper JSON test data)

| Domain | Workflow | Test Data Description |
|--------|----------|----------------------|
| genetics | analyze_cas9_mutation_outcomes | TP53 Cas9 editing with reference/edited sequences |
| genomics | gene_set_enrichment_analysis | Cell cycle gene list (CCNA2, CDK1, TP53, etc.) |
| microbiology | analyze_arsenic_speciation_hplc_icpms | HPLC-ICP-MS chromatogram data |
| microbiology | quantify_biofilm_biomass_crystal_violet | Crystal violet OD measurements |
| synthetic_biology | analyze_bacterial_growth_rate | E. coli growth curve OD600 data |
| synthetic_biology | analyze_barcode_sequencing_data | Inline mock FASTA with barcodes |
| synthetic_biology | analyze_bifurcation_diagram | Logistic map bifurcation data |
| synthetic_biology | create_biochemical_network_sbml_model | Enzymatic reaction network |
| synthetic_biology | simulate_gene_circuit_with_growth_feedback | Toggle switch circuit topology |
| physiology | analyze_abr_waveform_p1_metrics | ABR waveform time series data |
| physiology | perform_cosinor_analysis | 48h circadian temperature data |
| physiology | analyze_protein_colocalization | Inline mock fluorescence images |
| physiology | quantify_amyloid_beta_plaques | Inline mock histology image |
| immunology | track_immune_cells_under_flow | Inline mock image sequence |
| immunology | analyze_cns_lesion_histology | Inline mock H&E histology image |
| microbiology | predict_rna_secondary_structure | tRNA-Ala sequence |
| microbiology | annotate_bacterial_genome | Inline mock E. coli K12 FASTA |
| microbiology | simulate_generalized_lotka_volterra_dynamics | 3-species community model |
| microbiology | segment_and_analyze_microbial_cells | Inline mock fluorescence image |
| genetics | analyze_crispr_genome_editing | BRCA1 editing sequences |
| genetics | fit_genomic_prediction_model | Genotype matrix + phenotypes |
| microbiology | model_bacterial_growth_dynamics | E. coli batch culture parameters |
| microbiology | optimize_anaerobic_digestion_process | Food waste digestion optimization |
| molecular_biology | get_gene_coding_sequence | INS gene from Homo sapiens |
| molecular_biology | align_sequences | BRCA1 target sequence with primers |
| molecular_biology | design_golden_gate_oligos | BsaI cloning with backbone/insert |
| molecular_biology | golden_gate_assembly | BsaI-based fragment assembly |
| pharmacology | check_drug_combination_safety | Cardiovascular drug combo (aspirin, warfarin, metoprolol) |
| pharmacology | find_alternative_drugs_ddinter | Aspirin alternatives avoiding warfarin |
| bioengineering | perform_crispr_cas9_genome_editing | BRCA1 guide RNAs + target sequence |
| lab_automation | test_pylabrobot_script | Demo PyLabRobot liquid handling script |

## Workflows with Docker Library Issues

Most packages have now been installed in the biomni-tools Docker container. The following may still need attention:

| Package Status | Notes |
|----------------|-------|
| pylabrobot | INSTALLED - lab_automation workflows now work |
| nnunetv2 | INSTALLED - bioimaging/segment_with_nn_unet now works |
| biopython | INSTALLED - genetics, molecular_biology, database workflows work |
| scanpy | May need testing for genomics single-cell workflows |
| cv2 (opencv) | May need testing for pathology/cell_biology image workflows |

## Workflows Requiring External Files

These workflows need actual files (FCS, images, BAM) and cannot be tested with JSON params alone:

### Flow Cytometry (FCS files)
- immunology/analyze_cfse_cell_proliferation
- immunology/isolate_purify_immune_cells
- cell_biology/analyze_flow_cytometry_immunophenotyping
- cell_biology/perform_facs_cell_sorting

### Image Files
- pathology/quantify_corneal_nerve_fibers
- bioimaging/segment_with_nn_unet
- bioimaging/prepare_input_for_nnunet
- bioimaging/batch_register_images
- bioimaging/calculate_similarity_metrics
- biophysics/analyze_cell_morphology_and_cytoskeleton

### Genomic Data Files
- Various genomics workflows requiring BAM/VCF files

## Testing Instructions

Run individual workflow:
```bash
nextflow run subworkflows/{domain}/{workflow}/main.nf -profile docker
```

Test parameters are defined in:
- `main.nf` (default params)
- `tests/test.yml` (documented test cases)
