#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: planttfhunter — multi_species_tf_profiling
// Count and compare transcription factor family abundances across multiple species.
// Input: species_proteomes_directory, species_metadata.csv
// Container: quay.io/biocontainers/bioconductor-planttfhunter:1.10.0--r45hdfd78af_0
// R packages: Biostrings, SummarizedExperiment, planttfhunter
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-planttfhunter:1.10.0--r45hdfd78af_0"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biostrings", "SummarizedExperiment", "planttfhunter")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(planttfhunter)
    library(Biostrings)
    library(SummarizedExperiment)
    
    # Define input paths
    proteomes_dir <- "species_proteomes_directory"
    metadata_file <- "species_metadata.csv"
    
    # Check if inputs exist
    if (!dir.exists(proteomes_dir)) {
        stop(paste("Directory does not exist:", proteomes_dir))
    }
    if (!file.exists(metadata_file)) {
        stop(paste("Metadata file does not exist:", metadata_file))
    }
    
    # --- Read multiple proteome FASTA files into a named list of ---
    fasta_files <- list.files(proteomes_dir, pattern = "\\\\.(fa|fasta|faa|pep)\$", full.names = TRUE, ignore.case = TRUE)
    if (length(fasta_files) == 0) {
        stop(paste("No FASTA files found in", proteomes_dir))
    }
    
    proteomes <- lapply(fasta_files, Biostrings::readAAStringSet)
    names(proteomes) <- tools::file_path_sans_ext(basename(fasta_files))
    
    # --- Create a species metadata data frame with row names ---
    species_metadata <- read.csv(metadata_file, row.names = 1, stringsAsFactors = FALSE)
    
    # Align proteomes and metadata to ensure exact match of names
    common_species <- intersect(names(proteomes), rownames(species_metadata))
    if (length(common_species) == 0) {
        stop("No matching species names found between proteome files and species_metadata.csv row names.")
    }
    proteomes <- proteomes[common_species]
    species_metadata <- species_metadata[common_species, , drop = FALSE]
    
    # --- Run HMMER annotation and TF family counting across all ---
    if (!planttfhunter::hmmer_is_installed()) {
        stop("HMMER is not installed or not in the system PATH. planttfhunter requires HMMER to run.")
    }
    
    tf_counts <- get_tf_counts(proteomes, species_metadata)
    
    # --- Extract the TF count matrix and metadata from the ---
    counts_matrix <- SummarizedExperiment::assay(tf_counts)
    metadata_extracted <- SummarizedExperiment::colData(tf_counts)
    
    # Write outputs
    write.csv(as.data.frame(counts_matrix), "tf_counts_matrix.csv", row.names = TRUE)
    write.csv(as.data.frame(metadata_extracted), "tf_counts_metadata.csv", row.names = TRUE)
    saveRDS(tf_counts, "tf_counts_se.rds")
    
    message("Workflow completed successfully. Outputs saved to 'tf_counts_matrix.csv', 'tf_counts_metadata.csv', and 'tf_counts_se.rds'.")

    writeLines(c(
        '"BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING":',
        paste0('        planttfhunter: ', as.character(packageVersion("planttfhunter")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_species_tf_profiling.csv versions.yml
    """
}

workflow BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ species_proteomes_directory, species_metadata.csv ] ]

    main:
    BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING(ch_input)

    emit:
    tables   = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING.out.tables
    plots    = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING.out.plots
    objects  = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING.out.objects
    versions = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING.out.versions
}
