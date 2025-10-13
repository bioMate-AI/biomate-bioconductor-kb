# BioMni Tool Functions Analysis (2025-10-13)

## Executive Summary

**Total modules:** 18
**Total tool functions:** 182

## Functions by Module

| Module | Functions | Category |
|--------|-----------|----------|
| **database** | 35 | Database Query APIs |
| **pharmacology** | 18 | Drug & Pharmacology |
| **molecular_biology** | 18 | Molecular Biology |
| **microbiology** | 12 | Microbiology & Pathogens |
| **genomics** | 11 | Genomics & Sequencing |
| **immunology** | 10 | Immunology & Immune System |
| **physiology** | 10 | Physiology |
| **genetics** | 9 | Genetics & Variants |
| **synthetic_biology** | 8 | Synthetic Biology |
| **systems_biology** | 7 | Systems & Network Biology |
| **bioengineering** | 7 | Bioengineering |
| **pathology** | 7 | Pathology & Disease |
| **literature** | 7 | Literature & Publications |
| **biochemistry** | 6 | Biochemistry & Metabolism |
| **cancer_biology** | 6 | Cancer Biology |
| **cell_biology** | 5 | Cell Biology |
| **support_tools** | 3 | Support Tools |
| **biophysics** | 3 | Biophysics |

## Detailed Function Listings


### Biochemistry (6 functions)
**Category:** Biochemistry & Metabolism

1. **`analyze_circular_dichroism_spectra`**
   - **Description:** Analyzes circular dichroism (CD) spectroscopy data to determine secondary structure and thermal stability.
   - **Parameters:** sample_name: Any, sample_type: Any, wavelength_data: Any, cd_signal_data: Any, temperature_data: Any, thermal_cd_data: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

2. **`analyze_rna_secondary_structure_features`**
   - **Description:** Calculate numeric values for various structural features of an RNA secondary structure.
   - **Parameters:** dot_bracket_structure: Any, sequence: Any
   - **Note:** No @tool decorator (may be internal)

3. **`analyze_protease_kinetics`**
   - **Description:** Analyze protease kinetics data from fluorogenic peptide cleavage assays.
   - **Parameters:** time_points: Any, fluorescence_data: Any, substrate_concentrations: Any, enzyme_concentration: Any, output_prefix: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

4. **`analyze_enzyme_kinetics_assay`**
   - **Description:** Performs in vitro enzyme kinetics assay and analyzes the dose-dependent effects of modulators.
   - **Parameters:** enzyme_name: Any, substrate_concentrations: Any, enzyme_concentration: Any, modulators: Any, time_points: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

5. **`analyze_itc_binding_thermodynamics`**
   - **Description:** Analyzes isothermal titration calorimetry (ITC) data to determine binding affinity and thermodynamic parameters.
   - **Parameters:** itc_data_path: Any, itc_data: Any, temperature: Any, protein_concentration: Any, ligand_concentration: Any
   - **Note:** No @tool decorator (may be internal)

6. **`analyze_protein_conservation`**
   - **Description:** Perform multiple sequence alignment and phylogenetic analysis to identify conserved protein regions.
   - **Parameters:** protein_sequences: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)


### Bioengineering (7 functions)
**Category:** Bioengineering

1. **`analyze_cell_migration_metrics`**
   - **Description:** Analyze cell migration metrics from time-lapse microscopy images.
   - **Parameters:** image_sequence_path: Any, pixel_size_um: Any, time_interval_min: Any, min_track_length: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

2. **`perform_crispr_cas9_genome_editing`**
   - **Description:** Simulates CRISPR-Cas9 genome editing process including guide RNA design, delivery, and analysis.
   - **Parameters:** guide_rna_sequences: Any, target_genomic_loci: Any, cell_tissue_type: Any
   - **Note:** No @tool decorator (may be internal)

3. **`analyze_calcium_imaging_data`**
   - **Description:** Analyze calcium imaging data to quantify neuronal activity metrics.
   - **Parameters:** image_stack_path: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

4. **`analyze_in_vitro_drug_release_kinetics`**
   - **Description:** Analyzes in vitro drug release kinetics from biomaterial formulations.
   - **Parameters:** time_points: Any, concentration_data: Any, drug_name: Any, total_drug_loaded: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

5. **`analyze_myofiber_morphology`**
   - **Description:** Quantifies morphological properties of myofibers in microscopy images of tissue sections.
   - **Parameters:** image_path: Any, nuclei_channel: Any, myofiber_channel: Any, threshold_method: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

6. **`decode_behavior_from_neural_trajectories`**
   - **Description:** Model neural activity trajectories and decode behavioral variables.
   - **Parameters:** neural_data: Any, behavioral_data: Any, n_components: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

7. **`simulate_whole_cell_ode_model`**
   - **Description:** Simulate a whole-cell model represented as a system of ordinary differential equations (ODEs).
   - **Parameters:** initial_conditions: Any, parameters: Any, ode_function: Any, time_span: Any, 100): Any, time_points: Any, method: Any
   - **Note:** No @tool decorator (may be internal)


### Biophysics (3 functions)
**Category:** Biophysics

1. **`predict_protein_disorder_regions`**
   - **Description:** Predicts intrinsically disordered regions (IDRs) in a protein sequence using IUPred2A.
   - **Parameters:** protein_sequence: Any, threshold: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

2. **`analyze_cell_morphology_and_cytoskeleton`**
   - **Description:** Quantifies cell morphology and cytoskeletal organization from fluorescence microscopy images.
   - **Parameters:** image_path: Any, output_dir: Any, threshold_method: Any
   - **Note:** No @tool decorator (may be internal)

3. **`analyze_tissue_deformation_flow`**
   - **Description:** Quantify tissue deformation and flow dynamics from microscopy image sequence.
   - **Parameters:** image_sequence: Any, output_dir: Any, pixel_scale: Any
   - **Note:** No @tool decorator (may be internal)


### Cancer Biology (6 functions)
**Category:** Cancer Biology

1. **`analyze_ddr_network_in_cancer`**
   - **Description:** Analyze DNA Damage Response (DDR) network alterations and dependencies in cancer samples.
   - **Parameters:** expression_data_path: Any, mutation_data_path: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

2. **`analyze_cell_senescence_and_apoptosis`**
   - **Description:** Analyze flow cytometry data to quantify senescent and apoptotic cell populations.
   - **Parameters:** fcs_file_path: Any
   - **Note:** No @tool decorator (may be internal)

3. **`detect_and_annotate_somatic_mutations`**
   - **Description:** Detects and annotates somatic mutations in tumor samples compared to matched normal samples.
   - **Parameters:** tumor_bam: Any, normal_bam: Any, reference_genome: Any, output_prefix: Any, snpeff_database: Any
   - **Note:** No @tool decorator (may be internal)

4. **`detect_and_characterize_structural_variations`**
   - **Description:** Detects and characterizes structural variations (SVs) in genomic sequencing data.
   - **Parameters:** bam_file_path: Any, reference_genome_path: Any, output_dir: Any, cosmic_db_path: Any, clinvar_db_path: Any
   - **Note:** No @tool decorator (may be internal)

5. **`perform_gene_expression_nmf_analysis`**
   - **Description:** Performs Non-negative Matrix Factorization (NMF) on gene expression data to extract
   - **Parameters:** expression_data_path: Any, n_components: Any, normalize: Any, output_dir: Any, random_state: Any
   - **Note:** No @tool decorator (may be internal)

6. **`analyze_copy_number_purity_ploidy_and_focal_events`**
   - **Description:** CNVkit-based copy number workflow: CNV segmentation, purity/ploidy & HRD approximation, focal events.
   - **Parameters:** tumor_bam: Any, reference_genome: Any, normal_bam: Any, output_dir: Any, targets_bed: Any, antitargets_bed: Any, gene_bed: Any, focal_genes: Any, log2_amp_threshold: Any, log2_del_threshold: Any
   - **Note:** No @tool decorator (may be internal)


### Cell Biology (5 functions)
**Category:** Cell Biology

1. **`quantify_cell_cycle_phases_from_microscopy`**
   - **Description:** Quantify the percentage of cells in each cell cycle phase using Calcofluor white stained microscopy images.
   - **Parameters:** image_paths: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

2. **`quantify_and_cluster_cell_motility`**
   - **Description:** Quantify cell motility features from time-lapse microscopy images and cluster cells based on motility patterns.
   - **Parameters:** image_sequence_path: Any, output_dir: Any, num_clusters: Any
   - **Note:** No @tool decorator (may be internal)

3. **`perform_facs_cell_sorting`**
   - **Description:** Performs Fluorescence-Activated Cell Sorting (FACS) to enrich cell populations based on fluorescence characteristics.
   - **Parameters:** cell_suspension_data: Any, fluorescence_parameter: Any, threshold_min: Any, threshold_max: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

4. **`analyze_flow_cytometry_immunophenotyping`**
   - **Description:** Analyze flow cytometry data to identify and quantify specific cell populations based on surface markers.
   - **Parameters:** fcs_file_path: Any, gating_strategy: Any, compensation_matrix: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

5. **`analyze_mitochondrial_morphology_and_potential`**
   - **Description:** Quantifies metrics of mitochondrial morphology and membrane potential from fluorescence microscopy images.
   - **Parameters:** morphology_image_path: Any, potential_image_path: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)


### Database (35 functions)
**Category:** Database Query APIs

1. **`get_hpo_names`**
   - **Description:** Retrieve the names of given HPO terms.
   - **Parameters:** hpo_terms: list[str], data_lake_path: str
   - **Note:** No @tool decorator (may be internal)

2. **`query_uniprot`**
   - **Description:** Query the UniProt REST API using either natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, max_results: Any
   - **Note:** No @tool decorator (may be internal)

3. **`query_alphafold`**
   - **Description:** Query the AlphaFold Database API for protein structure predictions.
   - **Parameters:** uniprot_id: Any, endpoint: Any, residue_range: Any, download: Any, output_dir: Any, file_format: Any, model_version: Any, model_number: Any
   - **Note:** No @tool decorator (may be internal)

4. **`query_interpro`**
   - **Description:** Query the InterPro REST API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, max_results: Any
   - **Note:** No @tool decorator (may be internal)

5. **`query_pdb`**
   - **Description:** Query the RCSB PDB database using natural language or a direct structured query.
   - **Parameters:** prompt: Any, query: Any, max_results: Any
   - **Note:** No @tool decorator (may be internal)

6. **`query_pdb_identifiers`**
   - **Description:** Retrieve detailed data and/or download files for PDB identifiers.
   - **Parameters:** identifiers: Any, return_type: Any, download: Any, attributes: Any
   - **Note:** No @tool decorator (may be internal)

7. **`query_kegg`**
   - **Description:** Take a natural language prompt and convert it to a structured KEGG API query.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

8. **`query_stringdb`**
   - **Description:** Query the STRING protein interaction database using natural language or direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, download_image: Any, output_dir: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

9. **`query_iucn`**
   - **Description:** Query the IUCN Red List API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, token: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

10. **`query_paleobiology`**
   - **Description:** Query the Paleobiology Database (PBDB) API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

11. **`query_jaspar`**
   - **Description:** Query the JASPAR REST API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

12. **`query_worms`**
   - **Description:** Query the World Register of Marine Species (WoRMS) REST API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

13. **`query_cbioportal`**
   - **Description:** Query the cBioPortal REST API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

14. **`query_clinvar`**
   - **Description:** Take a natural language prompt and convert it to a structured ClinVar query.
   - **Parameters:** prompt: Any, search_term: Any, max_results: Any
   - **Note:** No @tool decorator (may be internal)

15. **`query_geo`**
   - **Description:** Query the NCBI Gene Expression Omnibus (GEO) using natural language or a direct search term.
   - **Parameters:** prompt: Any, search_term: Any, max_results: Any
   - **Note:** No @tool decorator (may be internal)

16. **`query_dbsnp`**
   - **Description:** Query the NCBI dbSNP database using natural language or a direct search term.
   - **Parameters:** prompt: Any, search_term: Any, max_results: Any
   - **Note:** No @tool decorator (may be internal)

17. **`query_ucsc`**
   - **Description:** Query the UCSC Genome Browser API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

18. **`query_ensembl`**
   - **Description:** Query the Ensembl REST API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

19. **`query_opentarget`**
   - **Description:** Query the OpenTargets Platform API using natural language or a direct GraphQL query.
   - **Parameters:** prompt: Any, query: Any, variables: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

20. **`query_monarch`**
   - **Description:** Query the Monarch Initiative API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, max_results: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

21. **`query_openfda`**
   - **Description:** Query the OpenFDA API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, max_results: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

22. **`query_clinicaltrials`**
   - **Description:** Query ClinicalTrials.gov API for clinical studies.
   - **Parameters:** prompt: str | None, endpoint: str | None, term: str | None, status: str | None, condition: str | None, intervention: str | None, location: str | None, phase: str | None, page_size: int, max_pages: int, page_token: str | None, verbose: bool
   - **Note:** No @tool decorator (may be internal)

23. **`query_gwas_catalog`**
   - **Description:** Query the GWAS Catalog API using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, max_results: Any
   - **Note:** No @tool decorator (may be internal)

24. **`query_gnomad`**
   - **Description:** Query gnomAD for variants in a gene using natural language or direct gene symbol.
   - **Parameters:** prompt: Any, gene_symbol: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

25. **`blast_sequence`**
   - **Description:** Identifies a DNA sequence using NCBI BLAST with improved error handling, timeout management, and debugging.
   - **Parameters:** sequence: str, database: str, program: str
   - **Note:** No @tool decorator (may be internal)

26. **`query_reactome`**
   - **Description:** Query the Reactome database using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, download: Any, output_dir: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

27. **`query_regulomedb`**
   - **Description:** Query the RegulomeDB database using natural language or direct variant/coordinate specification.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

28. **`query_pride`**
   - **Description:** Query the PRIDE (PRoteomics IDEntifications) database using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, max_results: Any
   - **Note:** No @tool decorator (may be internal)

29. **`query_gtopdb`**
   - **Description:** Query the Guide to PHARMACOLOGY database (GtoPdb) using natural language or a direct endpoint.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

30. **`region_to_ccre_screen`**
   - **Description:** Given starting and ending coordinates, this function retrieves information of intersecting cCREs.
   - **Parameters:** coord_chrom: str, coord_start: int, coord_end: int, assembly: str
   - **Note:** No @tool decorator (may be internal)

31. **`get_genes_near_ccre`**
   - **Description:** Given a cCRE (Candidate cis-Regulatory Element), this function returns a string containing the
   - **Parameters:** accession: str, assembly: str, chromosome: str, k: int
   - **Note:** No @tool decorator (may be internal)

32. **`query_remap`**
   - **Description:** Query the ReMap database for regulatory elements and transcription factor binding sites.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

33. **`query_mpd`**
   - **Description:** Query the Mouse Phenome Database (MPD) for mouse strain phenotype data.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

34. **`query_emdb`**
   - **Description:** Query the Electron Microscopy Data Bank (EMDB) for 3D macromolecular structures.
   - **Parameters:** prompt: Any, endpoint: Any, verbose: Any
   - **Note:** No @tool decorator (may be internal)

35. **`query_synapse`**
   - **Description:** Query Synapse REST API for biomedical datasets and files.
   - **Parameters:** prompt: str | None, query_term: str | list[str] | None, return_fields: list[str] | None, max_results: int, query_type: str, verbose: bool
   - **Note:** No @tool decorator (may be internal)


### Genetics (9 functions)
**Category:** Genetics & Variants

1. **`liftover_coordinates`**
   - **Description:** Perform liftover of genomic coordinates between hg19 and hg38 formats with detailed intermediate steps.
   - **Parameters:** chromosome: str, position: int, input_format: str, output_format: str, data_path: str
   - **Note:** No @tool decorator (may be internal)

2. **`bayesian_finemapping_with_deep_vi`**
   - **Description:** Performs Bayesian fine-mapping from GWAS summary statistics using deep variational inference.
   - **Parameters:** gwas_summary_path: Any, ld_matrix: Any, n_iterations: Any, learning_rate: Any, hidden_dim: Any, credible_threshold: Any
   - **Note:** No @tool decorator (may be internal)

3. **`analyze_cas9_mutation_outcomes`**
   - **Description:** Analyzes and categorizes mutations induced by Cas9 at target sites.
   - **Parameters:** reference_sequences: Any, edited_sequences: Any, cell_line_info: Any, output_prefix: Any
   - **Note:** No @tool decorator (may be internal)

4. **`analyze_crispr_genome_editing`**
   - **Description:** Analyzes CRISPR-Cas9 genome editing results by comparing original and edited sequences.
   - **Parameters:** original_sequence: Any, edited_sequence: Any, guide_rna: Any, repair_template: Any
   - **Note:** No @tool decorator (may be internal)

5. **`simulate_demographic_history`**
   - **Description:** Simulate DNA sequences with specified demographic and coalescent histories using msprime.
   - **Parameters:** num_samples: Any, sequence_length: Any, recombination_rate: Any, mutation_rate: Any, demographic_model: Any, demographic_params: Any, coalescent_model: Any, beta_coalescent_param: Any, random_seed: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

6. **`identify_transcription_factor_binding_sites`**
   - **Description:** Identifies binding sites for a specific transcription factor in a genomic sequence.
   - **Parameters:** sequence: Any, tf_name: Any, threshold: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

7. **`fit_genomic_prediction_model`**
   - **Description:** Fit a linear mixed model for genomic prediction using genotype and phenotype data.
   - **Parameters:** genotypes: Any, phenotypes: Any, fixed_effects: Any, model_type: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

8. **`perform_pcr_and_gel_electrophoresis`**
   - **Description:** Performs PCR amplification of a target transgene and visualizes results using agarose gel electrophoresis.
   - **Parameters:** genomic_dna: Any, forward_primer: Any, reverse_primer: Any, target_region: Any, annealing_temp: Any, extension_time: Any, cycles: Any, gel_percentage: Any, output_prefix: Any
   - **Note:** No @tool decorator (may be internal)

9. **`analyze_protein_phylogeny`**
   - **Description:** Perform phylogenetic analysis on a set of protein sequences.
   - **Parameters:** fasta_sequences: Any, output_dir: Any, alignment_method: Any, tree_method: Any
   - **Note:** No @tool decorator (may be internal)


### Genomics (11 functions)
**Category:** Genomics & Sequencing

1. **`annotate_celltype_scRNA`**
   - **Description:** Annotate cell types based on gene markers and transferred labels using LLM.
   - **Parameters:** adata_filename: Any, data_dir: Any, data_info: Any, data_lake_path: Any, cluster: Any, llm: Any, composition: Any
   - **Note:** No @tool decorator (may be internal)

2. **`annotate_celltype_with_panhumanpy`**
   - **Description:** Perform hierarchical cell type annotation using panhumanpy and Azimuth Neural Network.
   - **Parameters:** adata_path: Any, feature_names_col: Any, refine: Any, umap: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

3. **`create_scvi_embeddings_scRNA`**
   - **Description:** The UCE embeddings are usually our default tools to get cell embeddings, we map UCE embeddings to IMA referece dataset and get the cell types for a better understanding.
   - **Parameters:** adata_filename: Any, batch_key: Any, label_key: Any, data_dir): # Import scvi-tools correctly - the package name is still 'scvi' when installed
    try:
        import scvi
    except ImportError:
        return "Please install scvi-tools: pip install scvi-tools"

    steps, batch_key=batch_key)

    steps.append("Creating and training scVI model")
    model = scvi.model.SCVI(adata)
    model.train()

    steps.append("Generating latent representation using scVI")
    adata.obsm["X_scVI"] = model.get_latent_representation()

    steps.append(f"Creating scANVI model with label key: {label_key}")
    lvae, adata: Any, labels_key: Any, unlabeled_category: Any, )
    steps.append("Training scANVI model")
    lvae.train()

    steps.append("Generating latent representation using scANVI")
    adata.obsm["X_scANVI"]: Any, batch_key: Any, data_dir): # https://pypi.org/project/harmony-pytorch/
    from harmony import harmonize

    steps, adata.obs: Any, batch_key=batch_key)

    output_filename = f"{data_dir}/harmony_emb_data.h5ad"
    steps.append(f"Saving the Harmony embeddings to {output_filename}.")
    adata.write(output_filename)

    return "\n".join(steps)


## TODO: the environment is not ready for this tool
def get_uce_embeddings_scRNA(
    adata_filename, data_dir: Any, DATA_ROOT: Any, custom_args: Any
   - **Note:** No @tool decorator (may be internal)

4. **`map_to_ima_interpret_scRNA`**
   - **Description:** Map cell embeddings from the input dataset to the Integrated Megascale Atlas reference dataset using UCE embeddings.
   - **Parameters:** adata_filename: Any, data_dir: Any, custom_args: Any
   - **Note:** No @tool decorator (may be internal)

5. **`get_rna_seq_archs4`**
   - **Description:** Given a gene name, this function returns the steps it performs and the max K transcripts-per-million (TPM)
   - **Parameters:** gene_name: str, K: int
   - **Note:** No @tool decorator (may be internal)

6. **`get_gene_set_enrichment_analysis_supported_database_list`**
   - **Description:** Perform enrichment analysis for a list of genes, with optional background gene set and plotting functionality.
   - **Parameters:** None
   - **Note:** No @tool decorator (may be internal)

7. **`analyze_chromatin_interactions`**
   - **Description:** Analyze chromatin interactions from Hi-C data to identify enhancer-promoter interactions and TADs.
   - **Parameters:** hic_file_path: Any, regulatory_elements_bed: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

8. **`analyze_comparative_genomics_and_haplotypes`**
   - **Description:** Perform comparative genomics and haplotype analysis on multiple genome samples.
   - **Parameters:** sample_fasta_files: Any, reference_genome_path: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

9. **`perform_chipseq_peak_calling_with_macs2`**
   - **Description:** Perform ChIP-seq peak calling using MACS2 to identify genomic regions with significant binding.
   - **Parameters:** chip_seq_file: Any, control_file: Any, output_name: Any, genome_size: Any, q_value: Any
   - **Note:** No @tool decorator (may be internal)

10. **`find_enriched_motifs_with_homer`**
   - **Description:** Find DNA sequence motifs enriched in genomic regions using the HOMER motif discovery software.
   - **Parameters:** peak_file: Any, genome: Any, background_file: Any, motif_length: Any, 10: Any, 12": Any, output_dir: Any, num_motifs: Any, threads: Any
   - **Note:** No @tool decorator (may be internal)

11. **`analyze_genomic_region_overlap`**
   - **Description:** Analyze overlaps between two or more sets of genomic regions.
   - **Parameters:** region_sets: Any, output_prefix: Any
   - **Note:** No @tool decorator (may be internal)


### Immunology (10 functions)
**Category:** Immunology & Immune System

1. **`analyze_atac_seq_differential_accessibility`**
   - **Description:** Perform ATAC-seq peak calling and differential accessibility analysis using MACS2.
   - **Parameters:** treatment_bam: Any, control_bam: Any, output_dir: Any, genome_size: Any, q_value: Any, name_prefix: Any
   - **Note:** No @tool decorator (may be internal)

2. **`analyze_bacterial_growth_curve`**
   - **Description:** Analyzes bacterial growth curve data to determine growth parameters.
   - **Parameters:** time_points: Any, od_values: Any, strain_name: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

3. **`isolate_purify_immune_cells`**
   - **Description:** Simulates the isolation and purification of immune cells from tissue samples.
   - **Parameters:** tissue_type: Any, target_cell_type: Any, enzyme_type: Any, macs_antibody: Any, digestion_time_min: Any
   - **Note:** No @tool decorator (may be internal)

4. **`estimate_cell_cycle_phase_durations`**
   - **Description:** Estimate cell cycle phase durations using dual-nucleoside pulse labeling data and mathematical modeling.
   - **Parameters:** flow_cytometry_data: Any, initial_estimates: Any
   - **Note:** No @tool decorator (may be internal)

5. **`track_immune_cells_under_flow`**
   - **Description:** Track immune cells under flow conditions and classify their behaviors.
   - **Parameters:** image_sequence_path: Any, output_dir: Any, pixel_size_um: Any, time_interval_sec: Any, flow_direction: Any
   - **Note:** No @tool decorator (may be internal)

6. **`analyze_cfse_cell_proliferation`**
   - **Description:** Analyze CFSE-labeled cell samples to quantify cell division and proliferation.
   - **Parameters:** fcs_file_path: Any, cfse_channel: Any, lymphocyte_gate: Any
   - **Note:** No @tool decorator (may be internal)

7. **`analyze_cytokine_production_in_cd4_tcells`**
   - **Description:** Analyze cytokine production (IFN-γ, IL-17) in CD4+ T cells after antigen stimulation.
   - **Parameters:** fcs_files_dict: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

8. **`analyze_ebv_antibody_titers`**
   - **Description:** Analyze ELISA data to quantify EBV antibody titers in plasma/serum samples.
   - **Parameters:** raw_od_data: Any, standard_curve_data: Any, sample_metadata: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

9. **`analyze_cns_lesion_histology`**
   - **Description:** Analyzes histological images of CNS lesions to quantify immune cell infiltration,
   - **Parameters:** image_path: Any, output_dir: Any, stain_type: Any
   - **Note:** No @tool decorator (may be internal)

10. **`analyze_immunohistochemistry_image`**
   - **Description:** Analyzes immunohistochemistry images to quantify protein expression and spatial distribution.
   - **Parameters:** image_path: Any, protein_name: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)


### Literature (7 functions)
**Category:** Literature & Publications

1. **`fetch_supplementary_info_from_doi`**
   - **Description:** Fetches supplementary information for a paper given its DOI and returns a research log.
   - **Parameters:** doi: str, output_dir: str
   - **Note:** No @tool decorator (may be internal)

2. **`query_arxiv`**
   - **Description:** Query arXiv for papers based on the provided search query.
   - **Parameters:** query: str, max_papers: int
   - **Note:** No @tool decorator (may be internal)

3. **`query_scholar`**
   - **Description:** Query Google Scholar for papers based on the provided search query.
   - **Parameters:** query: str
   - **Note:** No @tool decorator (may be internal)

4. **`query_pubmed`**
   - **Description:** Query PubMed for papers based on the provided search query.
   - **Parameters:** query: str, max_papers: int, max_retries: int
   - **Note:** No @tool decorator (may be internal)

5. **`search_google`**
   - **Description:** Search using Google search.
   - **Parameters:** query: str, num_results: int, language: str
   - **Note:** No @tool decorator (may be internal)

6. **`extract_url_content`**
   - **Description:** Extract the text content of a webpage using requests and BeautifulSoup.
   - **Parameters:** url: str
   - **Note:** No @tool decorator (may be internal)

7. **`extract_pdf_content`**
   - **Description:** Extract the text content of a PDF file given its URL.
   - **Parameters:** url: str
   - **Note:** No @tool decorator (may be internal)


### Microbiology (12 functions)
**Category:** Microbiology & Pathogens

1. **`optimize_anaerobic_digestion_process`**
   - **Description:** Optimize anaerobic digestion process conditions to maximize VFA production or methane yield.
   - **Parameters:** waste_characteristics: Any, operational_parameters: Any, target_output: Any, optimization_method: Any
   - **Note:** No @tool decorator (may be internal)

2. **`analyze_arsenic_speciation_hplc_icpms`**
   - **Description:** Analyzes arsenic speciation in liquid samples using HPLC-ICP-MS technique.
   - **Parameters:** sample_data: Any, sample_name: Any, calibration_data: Any
   - **Note:** No @tool decorator (may be internal)

3. **`count_bacterial_colonies`**
   - **Description:** Count bacterial colonies from an image of agar plate using computer vision techniques.
   - **Parameters:** image_path: Any, dilution_factor: Any, plate_area_cm2: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

4. **`annotate_bacterial_genome`**
   - **Description:** Annotate a bacterial genome using Prokka to identify genes, proteins, and functional features.
   - **Parameters:** genome_file_path: Any, output_dir: Any, genus: Any, species: Any, strain: Any, prefix: Any
   - **Note:** No @tool decorator (may be internal)

5. **`enumerate_bacterial_cfu_by_serial_dilution`**
   - **Description:** Quantify bacterial concentration (CFU/mL) using serial dilutions and spot plating.
   - **Parameters:** initial_sample_volume_ml: Any, estimated_concentration: Any, dilution_factor: Any, num_dilutions: Any, spots_per_dilution: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

6. **`model_bacterial_growth_dynamics`**
   - **Description:** Model bacterial population dynamics over time using ordinary differential equations.
   - **Parameters:** initial_population: Any, growth_rate: Any, clearance_rate: Any, niche_size: Any, simulation_time: Any, time_step: Any
   - **Note:** No @tool decorator (may be internal)

7. **`quantify_biofilm_biomass_crystal_violet`**
   - **Description:** Quantifies biofilm biomass using crystal violet staining assay data.
   - **Parameters:** od_values: Any, sample_names: Any, control_index: Any, save_path: Any
   - **Note:** No @tool decorator (may be internal)

8. **`segment_and_analyze_microbial_cells`**
   - **Description:** Perform automated cell segmentation and quantify morphological metrics from fluorescence microscopy images.
   - **Parameters:** image_path: Any, output_dir: Any, min_cell_size: Any
   - **Note:** No @tool decorator (may be internal)

9. **`segment_cells_with_deep_learning`**
   - **Description:** Perform cell segmentation on fluorescence microscopy images using deep learning.
   - **Parameters:** image_path: Any, model_type: Any, diameter: Any, save_dir: Any
   - **Note:** No @tool decorator (may be internal)

10. **`simulate_generalized_lotka_volterra_dynamics`**
   - **Description:** Simulate microbial community dynamics using the Generalized Lotka-Volterra (gLV) model.
   - **Parameters:** initial_abundances: Any, growth_rates: Any, interaction_matrix: Any, time_points: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

11. **`predict_rna_secondary_structure`**
   - **Description:** Predict the secondary structure of an RNA molecule using ViennaRNA.
   - **Parameters:** rna_sequence: Any, output_prefix: Any
   - **Note:** No @tool decorator (may be internal)

12. **`simulate_microbial_population_dynamics`**
   - **Description:** Performs stochastic simulation of microbial population dynamics using the Gillespie algorithm.
   - **Parameters:** initial_populations: Any, growth_rates: Any, clearance_rates: Any, carrying_capacities: Any, max_time: Any, num_simulations: Any, time_points: Any
   - **Note:** No @tool decorator (may be internal)


### Molecular Biology (18 functions)
**Category:** Molecular Biology

1. **`annotate_open_reading_frames`**
   - **Description:** Find all Open Reading Frames (ORFs) in a DNA sequence using Biopython.
   - **Parameters:** sequence: Any, min_length: Any, search_reverse: Any, filter_subsets: Any
   - **Note:** No @tool decorator (may be internal)

2. **`annotate_plasmid`**
   - **Description:** Annotate a DNA sequence using pLannotate's command-line interface.
   - **Parameters:** sequence: str, is_circular: bool
   - **Note:** No @tool decorator (may be internal)

3. **`get_gene_coding_sequence`**
   - **Description:** Retrieves the coding sequence(s) of a specified gene from NCBI Entrez.
   - **Parameters:** gene_name: str, organism: str, email: str
   - **Note:** No @tool decorator (may be internal)

4. **`get_plasmid_sequence`**
   - **Description:** Unified function to retrieve plasmid sequences from either Addgene or NCBI.
   - **Parameters:** identifier: str, is_addgene: bool
   - **Note:** No @tool decorator (may be internal)

5. **`align_sequences`**
   - **Description:** Align short sequences (primers) to a longer sequence, allowing for one mismatch.
   - **Parameters:** long_seq: str, short_seqs: str | list[str]
   - **Note:** No @tool decorator (may be internal)

6. **`pcr_simple`**
   - **Description:** Simulate PCR amplification with given primers and sequence.
   - **Parameters:** sequence: str, forward_primer: str, reverse_primer: str, circular: bool
   - **Note:** No @tool decorator (may be internal)

7. **`digest_sequence`**
   - **Description:** Simulates restriction enzyme digestion using Biopython's catalyze method and returns the resulting DNA fragments.
   - **Parameters:** dna_sequence: str, enzyme_names: list[str], is_circular: bool
   - **Note:** No @tool decorator (may be internal)

8. **`find_restriction_sites`**
   - **Description:** Identifies restriction enzyme sites in a given DNA sequence for specified enzymes.
   - **Parameters:** dna_sequence: str, enzymes: list[str], is_circular: bool
   - **Note:** No @tool decorator (may be internal)

9. **`find_restriction_enzymes`**
   - **Description:** Finds common restriction enzyme sites in a DNA sequence.
   - **Parameters:** sequence: str, is_circular: bool
   - **Note:** No @tool decorator (may be internal)

10. **`find_sequence_mutations`**
   - **Description:** Compare query sequence against reference sequence to identify mutations.
   - **Parameters:** query_sequence: Any, reference_sequence: Any, query_start: Any
   - **Note:** No @tool decorator (may be internal)

11. **`design_knockout_sgrna`**
   - **Description:** Design sgRNAs for CRISPR knockout by searching pre-computed sgRNA libraries.
   - **Parameters:** gene_name: str, data_lake_path: str, species: str, num_guides: int
   - **Note:** No @tool decorator (may be internal)

12. **`get_oligo_annealing_protocol`**
   - **Description:** Return a standard protocol for annealing oligonucleotides without phosphorylation.
   - **Parameters:** None
   - **Note:** No @tool decorator (may be internal)

13. **`get_golden_gate_assembly_protocol`**
   - **Description:** Return a customized protocol for Golden Gate assembly based on the number of inserts
   - **Parameters:** num_inserts: int, enzyme_name: str, vector_length: int, vector_amount_ng: float, insert_lengths: list[int], is_library_prep: bool
   - **Note:** No @tool decorator (may be internal)

14. **`get_bacterial_transformation_protocol`**
   - **Description:** Return a standard protocol for bacterial transformation.
   - **Parameters:** antibiotic: str, is_repetitive: bool
   - **Note:** No @tool decorator (may be internal)

15. **`design_primer`**
   - **Description:** Design a single primer within the given sequence window.
   - **Parameters:** sequence: str, start_pos: int, primer_length: int, min_gc: float, max_gc: float, min_tm: float, max_tm: float, search_window: int
   - **Note:** No @tool decorator (may be internal)

16. **`design_verification_primers`**
   - **Description:** Design Sanger sequencing primers to verify a specific region in a plasmid.
   - **Parameters:** plasmid_sequence: str, target_region: tuple[int, int]: Any, existing_primers: list[dict[str, str]] | None: Any, is_circular: bool, coverage_length: int, primer_length: int, min_gc: float, max_gc: float, min_tm: float, max_tm: float
   - **Note:** No @tool decorator (may be internal)

17. **`design_golden_gate_oligos`**
   - **Description:** Design oligos for Golden Gate assembly by identifying backbone overhangs
   - **Parameters:** backbone_sequence: str, insert_sequence: str, enzyme_name: str, is_circular: bool
   - **Note:** No @tool decorator (may be internal)

18. **`golden_gate_assembly`**
   - **Description:** Simulate Golden Gate assembly to predict final construct sequences.
   - **Parameters:** backbone_sequence: str, enzyme_name: str, fragments: list[dict[str, str]]: Any, is_circular: bool
   - **Note:** No @tool decorator (may be internal)


### Pathology (7 functions)
**Category:** Pathology & Disease

1. **`analyze_aortic_diameter_and_geometry`**
   - **Description:** Analyze aortic diameter and geometry from cardiovascular imaging data.
   - **Parameters:** image_path: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

2. **`analyze_atp_luminescence_assay`**
   - **Description:** Analyze luminescence-based ATP assay data to determine intracellular ATP concentration.
   - **Parameters:** data_file: Any, standard_curve_file: Any, normalization_method: Any, normalization_data: Any
   - **Note:** No @tool decorator (may be internal)

3. **`analyze_thrombus_histology`**
   - **Description:** Analyze histological images of thrombus samples stained with H&E to identify and quantify
   - **Parameters:** image_path: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

4. **`analyze_intracellular_calcium_with_rhod2`**
   - **Description:** Analyzes intracellular calcium concentration using Rhod-2 fluorescent indicator from microscopy images.
   - **Parameters:** background_image_path: Any, control_image_path: Any, sample_image_path: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

5. **`quantify_corneal_nerve_fibers`**
   - **Description:** Quantify the volume/density of immunofluorescence-labeled corneal nerve fibers.
   - **Parameters:** image_path: Any, marker_type: Any, output_dir: Any, threshold_method: Any
   - **Note:** No @tool decorator (may be internal)

6. **`segment_and_quantify_cells_in_multiplexed_images`**
   - **Description:** Segment cells and quantify protein expression levels from multichannel tissue images.
   - **Parameters:** image_path: Any, markers_list: Any, nuclear_channel_index: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

7. **`analyze_bone_microct_morphometry`**
   - **Description:** Analyze bone microarchitecture parameters from 3D micro-CT images.
   - **Parameters:** input_file_path: Any, output_dir: Any, threshold_value: Any
   - **Note:** No @tool decorator (may be internal)


### Pharmacology (18 functions)
**Category:** Drug & Pharmacology

1. **`run_diffdock_with_smiles`**
   - **Description:** This function computes TxGNN model predictions for drug repurposing. It takes in the paths to the data,
   - **Parameters:** pdb_path: Any, smiles_string: Any, local_output_dir: Any, gpu_device: Any, use_gpu=True): try:
        summary, "pull": Any, "rbgcsail/diffdock"]: Any, check=True)
        summary.append("DiffDock container pulled successfully.")

        # Check for GPU availability (if using GPU)
        if use_gpu: summary.append("Checking for GPU availability...")
            gpu_check, "run": Any, "--rm": Any, "--gpus": Any, "all": Any, "nvidia/cuda: 11.7.1-devel-ubuntu22.04", "nvidia-smi": Any, ]: Any, check: Any, capture_output: Any, text: Any, )
            summary.append(f"GPU Status: {gpu_check.stdout.strip()}")

        # Prepare the GPU flag
        gpu_flag, f"device: Any, "run"]
            + gpu_flag
            + [
                # Mount the local directory to /home/appuser/output inside the container
                "-v": Any, f"{os.path.abspath(pdb_path)}: /home/appuser/input/protein.pdb", # PDB file mount
                "-v": Any, f"{os.path.abspath(local_output_dir)}: /home/appuser/output", # Output directory mount
                "--entrypoint": Any, "/bin/bash": Any, "rbgcsail/diffdock": Any, "-c": Any, # Command to run inference using micromamba environment
                f"micromamba run -n diffdock python -m inference --config default_inference_args.yaml "
                f"--protein_path /home/appuser/input/protein.pdb --ligand '{smiles_string}' --out_dir /home/appuser/output": Any, ]
        )

        # Execute the Docker command
        result: Any, check: Any, capture_output: Any, text=True)

        # Check for errors
        if result.returncode != 0: summary.append(f"Error during inference: {result.stderr.strip()}")
            return "\n".join(summary)
        else:
            summary.append("DiffDock inference completed successfully.")
            summary.append(f"Results stored in '{local_output_dir}'.")

        return "\n".join(summary)

    except FileNotFoundError as e:
        return f"File error: {e}"
    except subprocess.CalledProcessError as e:
        return f"Command execution error: {e}"
    except Exception as e:
        return f"An error occurred: {e}"


def docking_autodock_vina(smiles_list, receptor_pdb_file: Any, box_center: Any, box_size: Any, ncpu=1): from tdc import Oracle

    log, receptor_pdb_file: Any, box_center: Any, box_size: Any, ncpu: Any, )
    log.append("Oracle initialized successfully.")

    # Log the list of SMILES strings
    log.append(f"\nStep 2: Processing SMILES strings: {smiles_list}")

    # Get the docking scores
    docking_scores, docking_scores: Any, strict=False))

    # Log the result mapping
    log.append("\nStep 3: Mapping SMILES to docking scores:")
    log.append(f"Results: {results_dict}")

    # Convert the log to a string and return it
    research_log, output_dir: Any, spacing=1.0): # Prepare the output directory
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Convert the PDB file to PDBQT format (assuming prepare_receptor4.py is accessible)
    pdbqt_file, ".pdbqt")
    subprocess.run(["prepare_receptor": Any, "-r": Any, pdb_file: Any, "-o": Any, pdbqt_file]: Any, check: Any, "-r": Any, pdbqt_file: Any, "--spacing": Any, str(spacing): Any, "-o": Any, output_dir: Any, ]
    subprocess.run(autosite_cmd: Any, check: Any, box_size: Any, None
    log_path: Any, "_AutoSiteSummary.log")
    with open(log_path) as log_file: log_content, log_content)
        box_size_match = re.search(r"Box size: \s*\(([^)]+)\)", log_content)

        if box_center_match: box_center, data_lake_path: Any, k: Any
   - **Note:** No @tool decorator (may be internal)

2. **`predict_admet_properties`**
   - **Description:** Analyzes the stability of pharmaceutical formulations under accelerated storage conditions.
   - **Parameters:** smiles_list: Any, ADMET_model_type="MPNN"): try:
        from DeepPurpose import CompoundPred, utils
    except Exception: subprocess.run([sys.executable, "-m": Any, "pip": Any, "install": Any, "DeepPurpose"]: Any, check: Any, utils

    # Define available model types
    available_model_types: Any, "CNN": Any, "Morgan"]

    # Check if the provided model type is valid
    if ADMET_model_type not in available_model_types: return f"Error: Invalid ADMET model type '{ADMET_model_type}'. Available options are: {', '.join(available_model_types)}."

    # Load pretrained ADMET models only once
    model_ADMETs: Any, "Caco2": Any, "HIA": Any, "Pgp_inhibitor": Any, "Bioavailability": Any, "BBB_MolNet": Any, "PPBR": Any, "CYP2C19": Any, "CYP2D6": Any, "CYP3A4": Any, "CYP1A2": Any, "CYP2C9": Any, "ClinTox": Any, "Lipo_AZ": Any, "Half_life_eDrug3D": Any, "Clearance_eDrug3D": Any, ]

    for task in tasks: model_ADMETs[task + "_" + ADMET_model_type + "_model"], task: Any, unit): model, y: Any, drug_encoding: Any, split_method: Any, )
        y_pred = model.predict(X_pred)[0]

        if unit == "%": y_pred, "AqSolDB": Any, "log mol/L")
        lipophilicity: Any, "Lipo_AZ": Any, "(log-ratio)")
        research_log += f"- Solubility: {solubility}\n"
        research_log +, "Caco2": Any, "cm/s")
        hia: Any, "HIA": Any, "%")
        pgp: Any, "Pgp_inhibitor": Any, "%")
        bioavail: Any, "Bioavailability": Any, "%")
        research_log += f"- Absorption (Caco-2 permeability): {caco2}\n"
        research_log +, "BBB_MolNet": Any, "%")
        ppbr: Any, "PPBR": Any, "%")
        research_log += f"- Distribution (BBB permeation): {bbb}\n"
        research_log +, "CYP2C19": Any, "%")
        cyp2d6: Any, "CYP2D6": Any, "%")
        cyp3a4: Any, "CYP3A4": Any, "%")
        cyp1a2: Any, "CYP1A2": Any, "%")
        cyp2c9: Any, "CYP2C9": Any, "%")
        research_log += f"- Metabolism (CYP2C19): {cyp2c19}\n"
        research_log +, "Half_life_eDrug3D": Any, "h")
        clearance: Any, "Clearance_eDrug3D": Any, "mL/min/kg")
        research_log += f"- Excretion (Half-life): {half_life}\n"
        research_log +, "ClinTox": Any, "%")
        research_log += f"- Clinical Toxicity: {clinical_toxicity}\n"

        research_log +, amino_acid_sequence: Any, affinity_model_type="MPNN-CNN"): try:
        from DeepPurpose import DTI, utils
    except Exception: subprocess.run([sys.executable, "-m": Any, "pip": Any, "install": Any, "DeepPurpose"]: Any, check: Any, utils

    # Define available model types for Binding Affinity
    available_affinity_model_types: Any, "MPNN-CNN": Any, "Morgan-CNN": Any, "Morgan-AAC": Any, "Daylight-AAC": Any, ]

    # Check if the provided affinity model type is valid
    if affinity_model_type not in available_affinity_model_types: return f"Error: Invalid affinity model type '{affinity_model_type}'. Available options are: {', '.join(available_affinity_model_types)}."

    # Load the pre-trained affinity model
    model_DTI: Any, "_") + "_BindingDB")

    # Initialize research log string
    research_log = "Research Log for Binding Affinity Predictions: \n"
    research_log +, X_target: Any, y: Any, drug_encoding: Any, target_encoding: Any, split_method: Any, )
        y_pred = model_DTI.predict(X_pred)[0]
        y_pred_nM = 10 ** (-y_pred) / 1e-9

        research_log += f"Predicted Binding Affinity: {y_pred_nM:.2f} nM\n"
        research_log +, storage_conditions: Any, time_points: Any
   - **Note:** No @tool decorator (may be internal)

3. **`run_3d_chondrogenic_aggregate_assay`**
   - **Description:** Generates a detailed protocol for performing a 3D chondrogenic aggregate culture assay to evaluate compounds' effects on chondrogenesis.
   - **Parameters:** chondrocyte_cells: Any, test_compounds: Any, culture_duration_days: Any, measurement_intervals: Any
   - **Note:** No @tool decorator (may be internal)

4. **`grade_adverse_events_using_vcog_ctcae`**
   - **Description:** Grade and monitor adverse events in animal studies using the VCOG-CTCAE standard.
   - **Parameters:** clinical_data_file: Any
   - **Note:** No @tool decorator (may be internal)

5. **`analyze_radiolabeled_antibody_biodistribution`**
   - **Description:** Analyze biodistribution and pharmacokinetic profile of radiolabeled antibodies.
   - **Parameters:** time_points: Any, tissue_data: Any
   - **Note:** No @tool decorator (may be internal)

6. **`estimate_alpha_particle_radiotherapy_dosimetry`**
   - **Description:** Estimate radiation absorbed doses to tumor and normal organs for alpha-particle radiotherapeutics.
   - **Parameters:** biodistribution_data: Any, radiation_parameters: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

7. **`perform_mwas_cyp2c19_metabolizer_status`**
   - **Description:** Perform a Methylome-wide Association Study (MWAS) to identify CpG sites significantly associated with CYP2C19 metabolizer status.
   - **Parameters:** methylation_data_path: Any, metabolizer_status_path: Any, covariates_path: Any, pvalue_threshold: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

8. **`calculate_physicochemical_properties`**
   - **Description:** Calculate key physicochemical properties of a drug candidate molecule.
   - **Parameters:** smiles_string: Any
   - **Note:** No @tool decorator (may be internal)

9. **`analyze_xenograft_tumor_growth_inhibition`**
   - **Description:** Analyze tumor growth inhibition in xenograft models across different treatment groups.
   - **Parameters:** data_path: Any, time_column: Any, volume_column: Any, group_column: Any, subject_column: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

10. **`analyze_western_blot`**
   - **Description:** Performs densitometric analysis of Western blot images to quantify relative protein expression.
   - **Parameters:** blot_image_path: Any, target_bands: Any, loading_control_band: Any, antibody_info: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

11. **`query_drug_interactions`**
   - **Description:** Query drug-drug interactions from DDInter database.
   - **Parameters:** drug_names: Any, interaction_types: Any, severity_levels: Any, data_lake_path: Any
   - **Note:** No @tool decorator (may be internal)

12. **`check_drug_combination_safety`**
   - **Description:** Analyze safety of a drug combination for potential interactions.
   - **Parameters:** drug_list: Any, include_mechanisms: Any, include_management: Any, data_lake_path: Any
   - **Note:** No @tool decorator (may be internal)

13. **`analyze_interaction_mechanisms`**
   - **Description:** Analyze interaction mechanisms between two specific drugs.
   - **Parameters:** drug_pair: Any, detailed_analysis: Any, data_lake_path: Any
   - **Note:** No @tool decorator (may be internal)

14. **`find_alternative_drugs_ddinter`**
   - **Description:** Find alternative drugs that don't interact with contraindicated drugs.
   - **Parameters:** target_drug: Any, contraindicated_drugs: Any, therapeutic_class: Any, data_lake_path: Any
   - **Note:** No @tool decorator (may be internal)

15. **`query_fda_adverse_events`**
   - **Description:** Query FDA adverse event reports for specific drugs.
   - **Parameters:** drug_name: str, date_range: tuple[str, str] | None: Any, severity_filter: list[str] | None, outcome_filter: list[str] | None, limit: int
   - **Note:** No @tool decorator (may be internal)

16. **`get_fda_drug_label_info`**
   - **Description:** Retrieve FDA drug label information.
   - **Parameters:** drug_name: str, sections: list[str] | None
   - **Note:** No @tool decorator (may be internal)

17. **`check_fda_drug_recalls`**
   - **Description:** Check for FDA drug recalls and enforcement actions.
   - **Parameters:** drug_name: str, classification: list[str] | None, date_range: tuple[str, str] | None: Any
   - **Note:** No @tool decorator (may be internal)

18. **`analyze_fda_safety_signals`**
   - **Description:** Analyze safety signals across multiple drugs.
   - **Parameters:** drug_list: list[str], comparison_period: tuple[str, str] | None: Any, signal_threshold: float
   - **Note:** No @tool decorator (may be internal)


### Physiology (10 functions)
**Category:** Physiology

1. **`reconstruct_3d_face_from_mri`**
   - **Description:** Generate a 3D model of facial anatomy from MRI scans of the head and neck.
   - **Parameters:** mri_file_path: Any, output_dir: Any, subject_id: Any, threshold_value: Any
   - **Note:** No @tool decorator (may be internal)

2. **`analyze_abr_waveform_p1_metrics`**
   - **Description:** Extracts P1 amplitude and latency from Auditory Brainstem Response (ABR) waveform data.
   - **Parameters:** time_ms: Any, amplitude_uv: Any
   - **Note:** No @tool decorator (may be internal)

3. **`analyze_ciliary_beat_frequency`**
   - **Description:** Analyze ciliary beat frequency from high-speed video microscopy data using FFT analysis.
   - **Parameters:** video_path: Any, roi_count: Any, min_freq: Any, max_freq: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

4. **`analyze_protein_colocalization`**
   - **Description:** Analyze colocalization between two fluorescently labeled proteins in microscopy images.
   - **Parameters:** channel1_path: Any, channel2_path: Any, output_dir: Any, threshold_method: Any
   - **Note:** No @tool decorator (may be internal)

5. **`perform_cosinor_analysis`**
   - **Description:** Performs cosinor analysis on physiological time series data to characterize circadian rhythms.
   - **Parameters:** time_data: Any, physiological_data: Any, period: Any
   - **Note:** No @tool decorator (may be internal)

6. **`calculate_brain_adc_map`**
   - **Description:** Calculate Apparent Diffusion Coefficient (ADC) map from diffusion-weighted MRI data.
   - **Parameters:** dwi_file_path: Any, b_values: Any, output_path: Any, mask_file_path: Any
   - **Note:** No @tool decorator (may be internal)

7. **`analyze_endolysosomal_calcium_dynamics`**
   - **Description:** Analyze calcium dynamics in endo-lysosomal compartments using ELGA/ELGA1 probe data.
   - **Parameters:** time_points: Any, luminescence_values: Any, treatment_time: Any, cell_type: Any, treatment_name: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

8. **`analyze_fatty_acid_composition_by_gc`**
   - **Description:** Analyzes fatty acid composition in tissue samples using gas chromatography data.
   - **Parameters:** gc_data_file: Any, tissue_type: Any, sample_id: Any, output_directory: Any
   - **Note:** No @tool decorator (may be internal)

9. **`analyze_hemodynamic_data`**
   - **Description:** Analyzes raw blood pressure data to calculate key hemodynamic parameters.
   - **Parameters:** pressure_data: Any, sampling_rate: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

10. **`simulate_thyroid_hormone_pharmacokinetics`**
   - **Description:** Simulates the transport and binding of thyroid hormones across different tissue compartments
   - **Parameters:** parameters: Any, initial_conditions: Any, time_span: Any, 24): Any, time_points: Any
   - **Note:** No @tool decorator (may be internal)


### Support Tools (3 functions)
**Category:** Support Tools

1. **`run_python_repl`**
   - **Description:** Executes the provided Python command in a persistent environment and returns the output.
   - **Parameters:** command: str
   - **Note:** No @tool decorator (may be internal)

2. **`read_function_source_code`**
   - **Description:** Read the source code of a function from any module path.
   - **Parameters:** function_name: str
   - **Note:** No @tool decorator (may be internal)

3. **`download_synapse_data`**
   - **Description:** Download data from Synapse using entity IDs.
   - **Parameters:** entity_ids: str | list[str], download_location: str, follow_link: bool, recursive: bool, timeout: int, entity_type: str
   - **Note:** No @tool decorator (may be internal)


### Synthetic Biology (8 functions)
**Category:** Synthetic Biology

1. **`engineer_bacterial_genome_for_therapeutic_delivery`**
   - **Description:** Engineer a bacterial genome by integrating therapeutic genetic parts for therapeutic delivery.
   - **Parameters:** bacterial_genome_file: Any, genetic_parts: Any
   - **Note:** No @tool decorator (may be internal)

2. **`analyze_bacterial_growth_rate`**
   - **Description:** Analyze bacterial growth data and extract growth parameters from OD600 measurements.
   - **Parameters:** time_points: Any, od_measurements: Any, strain_name: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

3. **`analyze_barcode_sequencing_data`**
   - **Description:** Analyze sequencing data to extract, quantify and determine lineage relationships of barcodes.
   - **Parameters:** input_file: Any, barcode_pattern: Any, flanking_seq_5prime: Any, flanking_seq_3prime: Any, min_count: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

4. **`analyze_bifurcation_diagram`**
   - **Description:** Performs bifurcation analysis on a dynamical system and generates a bifurcation diagram.
   - **Parameters:** time_series_data: Any, parameter_values: Any, system_name: Any, output_dir: Any
   - **Note:** No @tool decorator (may be internal)

5. **`create_biochemical_network_sbml_model`**
   - **Description:** Generate a mathematical model of a biochemical network in SBML format.
   - **Parameters:** reaction_network: Any, kinetic_parameters: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

6. **`optimize_codons_for_heterologous_expression`**
   - **Description:** Analyzes and optimizes a DNA/RNA sequence for improved expression in a heterologous host organism.
   - **Parameters:** target_sequence: Any, host_codon_usage: Any
   - **Note:** No @tool decorator (may be internal)

7. **`simulate_gene_circuit_with_growth_feedback`**
   - **Description:** Simulate gene regulatory circuit dynamics with growth feedback.
   - **Parameters:** circuit_topology: Any, kinetic_params: Any, growth_params: Any, simulation_time: Any, time_points: Any
   - **Note:** No @tool decorator (may be internal)

8. **`identify_fas_functional_domains`**
   - **Description:** Identifies functional domains within a Fatty Acid Synthase (FAS) sequence and predicts their roles.
   - **Parameters:** sequence: Any, sequence_type: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)


### Systems Biology (7 functions)
**Category:** Systems & Network Biology

1. **`query_chatnt`**
   - **Description:** Call ChatNT to answer a question about a DNA sequence.
   - **Parameters:** question: Any, sequence: Any, device: Any
   - **Note:** No @tool decorator (may be internal)

2. **`perform_flux_balance_analysis`**
   - **Description:** Perform Flux Balance Analysis (FBA) on a genome-scale metabolic network model.
   - **Parameters:** model_file: Any, constraints: Any, objective_reaction: Any, output_file: Any
   - **Note:** No @tool decorator (may be internal)

3. **`model_protein_dimerization_network`**
   - **Description:** Model protein dimerization networks to find equilibrium concentrations of dimers.
   - **Parameters:** monomer_concentrations: Any, dimerization_affinities: Any, network_topology: Any
   - **Note:** No @tool decorator (may be internal)

4. **`simulate_metabolic_network_perturbation`**
   - **Description:** Construct and simulate kinetic models of metabolic networks and analyze their responses to perturbations.
   - **Parameters:** model_file: Any, initial_concentrations: Any, perturbation_params: Any, simulation_time: Any, time_points: Any
   - **Note:** No @tool decorator (may be internal)

5. **`simulate_protein_signaling_network`**
   - **Description:** Simulate protein signaling network dynamics using ODE-based logic modeling with normalized Hill functions.
   - **Parameters:** network_structure: Any, reaction_params: Any, species_params: Any, simulation_time: Any, time_points: Any
   - **Note:** No @tool decorator (may be internal)

6. **`compare_protein_structures`**
   - **Description:** Compares two protein structures to identify structural differences and conformational changes.
   - **Parameters:** pdb_file1: Any, pdb_file2: Any, chain_id1: Any, chain_id2: Any, output_prefix: Any
   - **Note:** No @tool decorator (may be internal)

7. **`simulate_renin_angiotensin_system_dynamics`**
   - **Description:** Simulate the time-dependent concentrations of renin-angiotensin system (RAS) components.
   - **Parameters:** initial_concentrations: Any, rate_constants: Any, feedback_params: Any, simulation_time: Any, time_points: Any
   - **Note:** No @tool decorator (may be internal)


## Recommendations for Galaxy Integration

### Priority 1: Database Query APIs (Database Module)

**35 functions** providing direct database access:

- `get_hpo_names`: Retrieve the names of given HPO terms.
- `query_uniprot`: Query the UniProt REST API using either natural language or a direct endpoint.
- `query_alphafold`: Query the AlphaFold Database API for protein structure predictions.
- `query_interpro`: Query the InterPro REST API using natural language or a direct endpoint.
- `query_pdb`: Query the RCSB PDB database using natural language or a direct structured query.
- `query_pdb_identifiers`: Retrieve detailed data and/or download files for PDB identifiers.
- `query_kegg`: Take a natural language prompt and convert it to a structured KEGG API query.
- `query_stringdb`: Query the STRING protein interaction database using natural language or direct endpoint.
- `query_iucn`: Query the IUCN Red List API using natural language or a direct endpoint.
- `query_paleobiology`: Query the Paleobiology Database (PBDB) API using natural language or a direct endpoint.

... and 25 more database query functions

**These should be converted to Galaxy tool wrappers as they:**
- Provide unique database access not available in Galaxy
- Return structured data that can be used in workflows
- Don't require complex tool installations

### Priority 2: Pharmacology & Drug Discovery

**18 functions** for drug discovery and pharmacology:

- `run_diffdock_with_smiles`: This function computes TxGNN model predictions for drug repurposing. It takes in the paths to the data,
- `predict_admet_properties`: Analyzes the stability of pharmaceutical formulations under accelerated storage conditions.
- `run_3d_chondrogenic_aggregate_assay`: Generates a detailed protocol for performing a 3D chondrogenic aggregate culture assay to evaluate compounds' effects on chondrogenesis.
- `grade_adverse_events_using_vcog_ctcae`: Grade and monitor adverse events in animal studies using the VCOG-CTCAE standard.
- `analyze_radiolabeled_antibody_biodistribution`: Analyze biodistribution and pharmacokinetic profile of radiolabeled antibodies.
- `estimate_alpha_particle_radiotherapy_dosimetry`: Estimate radiation absorbed doses to tumor and normal organs for alpha-particle radiotherapeutics.
- `perform_mwas_cyp2c19_metabolizer_status`: Perform a Methylome-wide Association Study (MWAS) to identify CpG sites significantly associated with CYP2C19 metabolizer status.
- `calculate_physicochemical_properties`: Calculate key physicochemical properties of a drug candidate molecule.
- `analyze_xenograft_tumor_growth_inhibition`: Analyze tumor growth inhibition in xenograft models across different treatment groups.
- `analyze_western_blot`: Performs densitometric analysis of Western blot images to quantify relative protein expression.

... and 8 more pharmacology functions

### Priority 3: Genomics & Molecular Biology

**29 functions** for sequence analysis and molecular data:

- `annotate_celltype_scRNA`: Annotate cell types based on gene markers and transferred labels using LLM.
- `annotate_celltype_with_panhumanpy`: Perform hierarchical cell type annotation using panhumanpy and Azimuth Neural Network.
- `create_scvi_embeddings_scRNA`: The UCE embeddings are usually our default tools to get cell embeddings, we map UCE embeddings to IMA referece dataset and get the cell types for a better understanding.
- `map_to_ima_interpret_scRNA`: Map cell embeddings from the input dataset to the Integrated Megascale Atlas reference dataset using UCE embeddings.
- `get_rna_seq_archs4`: Given a gene name, this function returns the steps it performs and the max K transcripts-per-million (TPM)
- `get_gene_set_enrichment_analysis_supported_database_list`: Perform enrichment analysis for a list of genes, with optional background gene set and plotting functionality.
- `analyze_chromatin_interactions`: Analyze chromatin interactions from Hi-C data to identify enhancer-promoter interactions and TADs.
- `analyze_comparative_genomics_and_haplotypes`: Perform comparative genomics and haplotype analysis on multiple genome samples.
- `perform_chipseq_peak_calling_with_macs2`: Perform ChIP-seq peak calling using MACS2 to identify genomic regions with significant binding.
- `find_enriched_motifs_with_homer`: Find DNA sequence motifs enriched in genomic regions using the HOMER motif discovery software.

## Implementation Strategy

1. **Database APIs** → Galaxy Data Source tools
   - Wrap Python functions in Galaxy XML
   - Return tabular/JSON outputs
   - 31 priority functions

2. **Analysis Functions** → Galaxy Tools
   - Convert to standalone Galaxy tools
   - Add proper input/output handling
   - ~50-70 high-value functions

3. **Data Lakes** → Galaxy Data Libraries
   - Expose pre-computed datasets
   - 79 curated datasets

**Total potential tools to add:** ~150+ Galaxy wrappers

---
*Generated: 2025-10-13*
*Source: bioMni /Users/jingqiwang/biomni*
