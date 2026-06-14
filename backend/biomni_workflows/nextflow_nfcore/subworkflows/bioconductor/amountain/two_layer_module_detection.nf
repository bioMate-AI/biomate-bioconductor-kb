#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AMOUNTAIN — two_layer_module_detection
// Identify active gene modules across two network layers simultaneously while maximizing inter-layer links.
// Input: W1, z1, W2, z2, A
// Container: quay.io/biocontainers/bioconductor-amountain:1.36.0--r45h57f0213_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AMOUNTAIN
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run moduleIdentificationGPFixSSTwolayer using the networks, node scores, and inter-layer weight matrix
//  * 2. [Core Analysis] Extract predicted module member indices for both layers

nextflow.enable.dsl = 2

process BIOC_AMOUNTAIN_TWO_LAYER_MODULE_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("AMOUNTAIN")
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
    
    # Load required library
    library(AMOUNTAIN)
    
    # Helper function to robustly read matrices and vectors
    read_input <- function(filepath, is_matrix = TRUE) {
      df <- tryCatch({
        read.csv(filepath, header = FALSE)
      }, error = function(e) {
        read.table(filepath, header = FALSE)
      })
      
      if (is_matrix) {
        return(as.matrix(df))
      } else {
        if (ncol(df) == 1) {
          return(as.numeric(df[[1]]))
        } else if (nrow(df) == 1) {
          return(as.numeric(df[1, ]))
        } else {
          return(as.numeric(df[[1]]))
        }
      }
    }
    
    # Read user input files from the working directory
    W1 <- read_input("W1.csv", is_matrix = TRUE)
    z1 <- read_input("z1.csv", is_matrix = FALSE)
    W2 <- read_input("W2.csv", is_matrix = TRUE)
    z2 <- read_input("z2.csv", is_matrix = FALSE)
    A  <- read_input("A.csv", is_matrix = TRUE)
    
    # Setup variables to match the documented code structure
    pp <- list(W1, z1)
    pp2 <- list(W2, z2)
    n1 <- nrow(W1)
    n2 <- nrow(W2)
    
    # Run the documented workflow
    modres <- moduleIdentificationGPFixSSTwolayer(pp[[1]], pp[[2]], rep(1/n1, n1), pp2[[1]], pp2[[2]], rep(1/n2, n2), A)
    predictedid <- which(modres[[1]] != 0)
    predictedid2 <- which(modres[[2]] != 0)
    
    # Save outputs
    saveRDS(modres, file = "module_results.rds")
    
    write.csv(data.frame(NodeIndex = predictedid), file = "predicted_indices_layer1.csv", row.names = FALSE)
    write.csv(data.frame(NodeIndex = predictedid2), file = "predicted_indices_layer2.csv", row.names = FALSE)
    
    write.csv(data.frame(Score = modres[[1]]), file = "module_scores_layer1.csv", row.names = FALSE)
    write.csv(data.frame(Score = modres[[2]]), file = "module_scores_layer2.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_AMOUNTAIN_TWO_LAYER_MODULE_DETECTION":',
        paste0('    AMOUNTAIN: ', as.character(packageVersion('AMOUNTAIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_layer_module_detection.csv versions.yml
    """
}

workflow BIOC_AMOUNTAIN_TWO_LAYER_MODULE_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ W1, z1, W2, z2, A ] ]

    main:
    BIOC_AMOUNTAIN_TWO_LAYER_MODULE_DETECTION(ch_input)

    emit:
    tables   = BIOC_AMOUNTAIN_TWO_LAYER_MODULE_DETECTION.out.tables
    plots    = BIOC_AMOUNTAIN_TWO_LAYER_MODULE_DETECTION.out.plots
    objects  = BIOC_AMOUNTAIN_TWO_LAYER_MODULE_DETECTION.out.objects
    versions = BIOC_AMOUNTAIN_TWO_LAYER_MODULE_DETECTION.out.versions
}
