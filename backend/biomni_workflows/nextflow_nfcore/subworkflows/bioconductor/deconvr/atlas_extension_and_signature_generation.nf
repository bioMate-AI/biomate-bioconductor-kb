#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deconvR — atlas_extension_and_signature_generation
// Extend an existing reference atlas with new sample data or construct tissue-specific CpG/DMP signature matrices.
// Input: samples, sampleMeta, HumanCellTypeMethAtlas
// Container: quay.io/biocontainers/bioconductor-deconvr:1.16.0--r45hdfd78af_0
// R packages: data.table, deconvR, dplyr
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, deconvR, dplyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare new sample data and metadata
//  * 2. [Core Analysis] Extend the reference atlas using findSignatures
//  * 3. [Input & Preparation] Construct tissue-specific CpG signature matrices or DMPs by setting tissueSpecCpGs or tissueSpecDMPs to TRUE in findSignatures

nextflow.enable.dsl = 2

process BIOC_DECONVR_ATLAS_EXTENSION_AND_SIGNATURE_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("data.table", "deconvR", "dplyr")
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
    library(deconvR)
    library(data.table)
    library(dplyr)
    
    # Helper function to read user input files from the working directory
    read_input <- function(base_name) {
      if (file.exists(paste0(base_name, ".rds"))) {
        return(readRDS(paste0(base_name, ".rds")))
      } else if (file.exists(paste0(base_name, ".csv"))) {
        return(read.csv(paste0(base_name, ".csv"), check.names = FALSE, stringsAsFactors = FALSE))
      } else if (file.exists(paste0(base_name, ".tsv"))) {
        return(read.delim(paste0(base_name, ".tsv"), check.names = FALSE, stringsAsFactors = FALSE))
      } else if (file.exists(base_name)) {
        return(readRDS(base_name))
      } else {
        stop(paste("Required input file not found:", base_name))
      }
    }
    
    # 1. Prepare new sample data and metadata
    message("Loading user input files...")
    samples <- read_input("samples")
    sampleMeta <- data.table::as.data.table(read_input("sampleMeta"))
    HumanCellTypeMethAtlas <- read_input("HumanCellTypeMethAtlas")
    
    # Ensure the first column of samples and atlas is named "IDs" for the first findSignatures call
    colnames(samples)[1] <- "IDs"
    colnames(HumanCellTypeMethAtlas)[1] <- "IDs"
    
    # 2. Extend the reference atlas using findSignatures
    message("Extending the reference atlas...")
    extended_matrix <- findSignatures(samples = samples, 
                                     sampleMeta = sampleMeta, 
                                     atlas = HumanCellTypeMethAtlas,
                                     IDs = "IDs")
    
    # Save the extended matrix
    write.csv(extended_matrix, "extended_matrix.csv", row.names = FALSE)
    message("Saved extended reference atlas to 'extended_matrix.csv'")
    
    # 3. Construct tissue-specific CpG signature matrices or DMPs
    # Prepare data for tissue-specific signature generation
    exampleSamples <- samples
    exampleMeta <- sampleMeta
    
    # Rename the ID columns to "CpGs" to match the documented code requirements
    colnames(exampleSamples)[1] <- "CpGs"
    colnames(HumanCellTypeMethAtlas)[1] <- "CpGs"
    
    # Construct tissue-specific CpG signature matrix (tissueSpecCpGs = TRUE)
    message("Constructing tissue-specific CpG signature matrix...")
    signatures <- findSignatures(
      samples = exampleSamples,
      sampleMeta = exampleMeta,
      atlas = HumanCellTypeMethAtlas,
      IDs = "CpGs", K = 100, tissueSpecCpGs = TRUE)
    
    # Save tissue-specific CpG signatures
    saveRDS(signatures, "signatures_tissueSpecCpGs.rds")
    message("Saved tissue-specific CpG signatures to 'signatures_tissueSpecCpGs.rds'")
    
    # Construct tissue-specific DMPs (tissueSpecDMPs = TRUE)
    message("Constructing tissue-specific DMPs...")
    signatures <- findSignatures(
      samples = exampleSamples,
      sampleMeta = exampleMeta,
      atlas = HumanCellTypeMethAtlas,
      IDs = "CpGs", tissueSpecDMPs = TRUE)
    
    # Save tissue-specific DMPs
    saveRDS(signatures, "signatures_tissueSpecDMPs.rds")
    message("Saved tissue-specific DMPs to 'signatures_tissueSpecDMPs.rds'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_DECONVR_ATLAS_EXTENSION_AND_SIGNATURE_GENERATION":',
        paste0('    deconvR: ', as.character(packageVersion('deconvR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_atlas_extension_and_signature_generation.csv versions.yml
    """
}

workflow BIOC_DECONVR_ATLAS_EXTENSION_AND_SIGNATURE_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples, sampleMeta, HumanCellTypeMethAtlas ] ]

    main:
    BIOC_DECONVR_ATLAS_EXTENSION_AND_SIGNATURE_GENERATION(ch_input)

    emit:
    tables   = BIOC_DECONVR_ATLAS_EXTENSION_AND_SIGNATURE_GENERATION.out.tables
    plots    = BIOC_DECONVR_ATLAS_EXTENSION_AND_SIGNATURE_GENERATION.out.plots
    objects  = BIOC_DECONVR_ATLAS_EXTENSION_AND_SIGNATURE_GENERATION.out.objects
    versions = BIOC_DECONVR_ATLAS_EXTENSION_AND_SIGNATURE_GENERATION.out.versions
}
