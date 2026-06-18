#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RGSEA — rgsea_fixed_features
// Classify query transcriptome samples against a reference dataset using a fixed number of top/bottom features and predict class probabilities.
// Input: query_matrix.csv, reference_matrix.csv
// Container: quay.io/biocontainers/bioconductor-rgsea:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RGSEA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run RGSEAfix to calculate similarity scores using a fixed number of features
//  * 2. [Core Analysis] View the classification matrix
//  * 3. [Core Analysis] Predict relative class probabilities using RGSEApredict

nextflow.enable.dsl = 2

process BIOC_RGSEA_RGSEA_FIXED_FEATURES {
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
    .bm_deps <- c("RGSEA")
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
    
    # Load the required library
    library(RGSEA)
    
    # Verify that the required user input files exist in the working directory
    if (!file.exists("query_matrix.csv")) {
      stop("Error: 'query_matrix.csv' not found in the working directory.")
    }
    if (!file.exists("reference_matrix.csv")) {
      stop("Error: 'reference_matrix.csv' not found in the working directory.")
    }
    
    # Read the expression matrices
    e1 <- as.matrix(read.csv("query_matrix.csv", row.names = 1, check.names = FALSE))
    e2 <- as.matrix(read.csv("reference_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Align features (rows) between query and reference datasets
    common_features <- intersect(rownames(e1), rownames(e2))
    if (length(common_features) == 0) {
      stop("Error: No common features (row names) found between query and reference matrices.")
    }
    e1 <- e1[common_features, , drop = FALSE]
    e2 <- e2[common_features, , drop = FALSE]
    
    # Determine robust parameters based on the actual number of common features
    num_features <- length(common_features)
    random_val <- min(20000, num_features)
    featurenum_val <- min(1000, floor(random_val / 2))
    
    # Ensure featurenum_val is at least 1
    if (featurenum_val < 1) {
      featurenum_val <- 1
    }
    
    # 1. Run RGSEAfix to calculate similarity scores using a fixed number of features
    RGSEAfix(e1, e2, queryclasses=colnames(e1), refclasses=colnames(e2), random=random_val, 
             featurenum=featurenum_val, iteration=100)->test
    
    # 2. View and save the classification matrix
    classification_matrix <- test[[1]]
    write.csv(classification_matrix, "classification_matrix.csv", row.names = TRUE)
    
    # 3. Predict relative class probabilities using RGSEApredict
    RGSEApredict(test[[1]], colnames(e2))->predictions
    write.csv(predictions, "predicted_probabilities.csv", row.names = TRUE)
    
    # Save the full RGSEA result object
    saveRDS(test, "rgsea_result.rds")

    writeLines(c(
        '"BIOC_RGSEA_RGSEA_FIXED_FEATURES":',
        paste0('    RGSEA: ', as.character(packageVersion('RGSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgsea_fixed_features.csv versions.yml
    """
}

workflow BIOC_RGSEA_RGSEA_FIXED_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query_matrix.csv, reference_matrix.csv ] ]

    main:
    BIOC_RGSEA_RGSEA_FIXED_FEATURES(ch_input)

    emit:
    tables   = BIOC_RGSEA_RGSEA_FIXED_FEATURES.out.tables
    plots    = BIOC_RGSEA_RGSEA_FIXED_FEATURES.out.plots
    objects  = BIOC_RGSEA_RGSEA_FIXED_FEATURES.out.objects
    versions = BIOC_RGSEA_RGSEA_FIXED_FEATURES.out.versions
}
