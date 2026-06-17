#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BERT — reference_based_correction
// Perform batch-effect correction using reference samples (bridges) when class distributions are severely skewed across batches.
// Input: expression_data_with_references.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BERT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the expression data containing the Reference column
//  * 2. [Core Analysis] Run BERT batch correction with method set to "ref"

nextflow.enable.dsl = 2

process BIOC_BERT_REFERENCE_BASED_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("BERT")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(BERT)
    
    # 1. Load the expression data containing the Reference column
    input_file <- "expression_data_with_references.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    dataset_raw <- read.csv(input_file, check.names = FALSE)
    
    # If the first column contains unique character/factor identifiers, set them as row names
    if (ncol(dataset_raw) > 0 && (is.character(dataset_raw[[1]]) || is.factor(dataset_raw[[1]]))) {
      if (!any(duplicated(dataset_raw[[1]]))) {
        rownames(dataset_raw) <- dataset_raw[[1]]
        dataset_raw <- dataset_raw[, -1, drop = FALSE]
      }
    }
    
    # 2. Run BERT batch correction with method set to "ref"
    dataset_adjusted <- BERT(dataset_raw, method="ref")
    
    # 3. Save the meaningful results
    write.csv(dataset_adjusted, "dataset_adjusted.csv", row.names = TRUE)
    saveRDS(dataset_adjusted, "dataset_adjusted.rds")

    writeLines(c(
        '"BIOC_BERT_REFERENCE_BASED_CORRECTION":',
        paste0('    BERT: ', as.character(packageVersion('BERT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_based_correction.csv versions.yml
    """
}

workflow BIOC_BERT_REFERENCE_BASED_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data_with_references.csv ] ]

    main:
    BIOC_BERT_REFERENCE_BASED_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BERT_REFERENCE_BASED_CORRECTION.out.tables
    plots    = BIOC_BERT_REFERENCE_BASED_CORRECTION.out.plots
    objects  = BIOC_BERT_REFERENCE_BASED_CORRECTION.out.objects
    versions = BIOC_BERT_REFERENCE_BASED_CORRECTION.out.versions
}
