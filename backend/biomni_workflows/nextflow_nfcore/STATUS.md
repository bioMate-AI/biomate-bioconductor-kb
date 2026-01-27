# Workflow Test Status

Last updated: 2026-01-27

## Summary
- **Total modules**: 235 (2 archived due to broken external APIs)
- **Passed with proper test data**: ~170
- **Needs external files**: ~30 (FCS, images, BAM files)
- **Needs investigation**: ~35

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
