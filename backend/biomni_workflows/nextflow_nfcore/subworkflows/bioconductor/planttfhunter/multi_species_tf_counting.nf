#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: planttfhunter — multi_species_tf_counting
// Count transcription factors per family across multiple species and integrate with species metadata.
// Input: proteomes_directory, metadata.csv
// Container: quay.io/biocontainers/bioconductor-planttfhunter:1.10.0--r45hdfd78af_0
// Requires: Biostrings, SummarizedExperiment, planttfhunter
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load proteomes as a list of AAStringSet objects
//  * 2. [Input & Preparation] Prepare species metadata data frame with row names matching the proteome list names
//  * 3. [Core Analysis] Check if HMMER is installed
//  * 4. [Visualization & Output] Run get_tf_counts() to obtain a SummarizedExperiment object
//  * 5. [Core Analysis] Extract counts matrix and metadata using assay() and colData()

nextflow.enable.dsl = 2

process BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_COUNTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(planttfhunter)
    library(Biostrings)
    library(SummarizedExperiment)
    
    set.seed(123) # for reproducibility
    
    # Define input paths
    proteomes_dir <- "proteomes_directory"
    metadata_file <- "metadata.csv"
    
    # Validate inputs
    if (!dir.exists(proteomes_dir)) {
        stop("Error: Proteomes directory '", proteomes_dir, "' does not exist.")
    }
    if (!file.exists(metadata_file)) {
        stop("Error: Metadata file '", metadata_file, "' does not exist.")
    }
    
    # 1. Load proteomes as a list of AAStringSet objects
    fasta_files <- list.files(proteomes_dir, pattern = "\\\\.(fa|fasta|faa|FA|FASTA|FAA)\$", full.names = TRUE)
    if (length(fasta_files) == 0) {
        stop("Error: No FASTA files found in '", proteomes_dir, "'.")
    }
    
    proteomes <- lapply(fasta_files, Biostrings::readAAStringSet)
    names(proteomes) <- tools::file_path_sans_ext(basename(fasta_files))
    
    # 2. Prepare species metadata data frame with row names matching the proteome list names
    species_metadata <- read.csv(metadata_file, row.names = 1, stringsAsFactors = FALSE)
    
    # Align proteomes and metadata to ensure exact matching of names
    common_species <- intersect(names(proteomes), rownames(species_metadata))
    if (length(common_species) == 0) {
        stop("Error: No matching species names found between FASTA file names and metadata row names.")
    }
    
    proteomes <- proteomes[common_species]
    species_metadata <- species_metadata[common_species, , drop = FALSE]
    
    # 3. Check if HMMER is installed
    if (!hmmer_is_installed()) {
        stop("Error: HMMER is not installed or not available in the system's PATH. planttfhunter requires HMMER to run.")
    }
    
    # 4. Run get_tf_counts() to obtain a SummarizedExperiment object
    tf_counts <- get_tf_counts(proteomes, species_metadata)
    
    # Take a look at the SummarizedExperiment object
    print(tf_counts)
    
    # 5. Extract counts matrix and metadata using assay() and colData()
    counts_matrix <- SummarizedExperiment::assay(tf_counts)
    metadata_extracted <- SummarizedExperiment::colData(tf_counts)
    
    # Print extracted elements to console
    print(counts_matrix)
    print(metadata_extracted)
    
    # 6. Write named output files for the meaningful results
    saveRDS(tf_counts, file = "tf_counts_se.rds")
    write.csv(as.matrix(counts_matrix), file = "tf_counts_matrix.csv", row.names = TRUE)
    write.csv(as.data.frame(metadata_extracted), file = "tf_counts_metadata.csv", row.names = TRUE)
    
    cat("Pipeline completed successfully. Outputs saved to 'tf_counts_se.rds', 'tf_counts_matrix.csv', and 'tf_counts_metadata.csv'.\n")

    writeLines(c(
        '"BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_COUNTING":',
        paste0('    planttfhunter: ', as.character(packageVersion('planttfhunter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_species_tf_counting.csv versions.yml
    """
}

workflow BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_COUNTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteomes_directory, metadata.csv ] ]

    main:
    BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_COUNTING(ch_input)

    emit:
    tables   = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_COUNTING.out.tables
    plots    = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_COUNTING.out.plots
    objects  = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_COUNTING.out.objects
    versions = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_COUNTING.out.versions
}
