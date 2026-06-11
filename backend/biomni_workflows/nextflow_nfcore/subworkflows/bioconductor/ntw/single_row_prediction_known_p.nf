#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NTW — single_row_prediction_known_p
// Estimate a single row of the gene interaction matrix (A) when the perturbation matrix (P) is already known.
// Input: gene_expression.csv, known_perturbations.csv, prior_network.csv
// Container: quay.io/biocontainers/bioconductor-ntw:1.60.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: NTW, mvtnorm
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the gene expression data and convert to a matrix
//  * 2. [Core Analysis] Set algorithm parameters (restK, topD, topK)
//  * 3. [Input & Preparation] Load or define the known perturbation matrix P.known
//  * 4. [Core Analysis] Estimate a single row of A using A.estimation.Srow

nextflow.enable.dsl = 2

process BIOC_NTW_SINGLE_ROW_PREDICTION_KNOWN_P {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("NTW", "mvtnorm")
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
    library(NTW)
    library(mvtnorm)
    
    # 1. Load the gene expression data and convert to a matrix
    if (!file.exists("gene_expression.csv")) {
      stop("Error: 'gene_expression.csv' is required but was not found in the working directory.")
    }
    X_df <- read.csv("gene_expression.csv", row.names = 1, check.names = FALSE)
    X <- as.matrix(X_df)
    
    # 2. Load or define the known perturbation matrix P.known
    if (!file.exists("known_perturbations.csv")) {
      stop("Error: 'known_perturbations.csv' is required but was not found in the working directory.")
    }
    P_df <- read.csv("known_perturbations.csv", row.names = 1, check.names = FALSE)
    P.known <- as.matrix(P_df)
    
    # Validate dimensions of P.known
    if (nrow(P.known) != nrow(X) || ncol(P.known) != ncol(X)) {
      stop(sprintf("Error: Dimensions of P.known (%dx%d) must match X (%dx%d).", 
                   nrow(P.known), ncol(P.known), nrow(X), ncol(X)))
    }
    
    # 3. Load or define the prior network matrix pred.net
    if (file.exists("prior_network.csv")) {
      pred_df <- read.csv("prior_network.csv", row.names = 1, check.names = FALSE)
      pred.net <- as.matrix(pred_df)
      # Validate dimensions of pred.net
      if (nrow(pred.net) != nrow(X) || ncol(pred.net) != nrow(X)) {
        stop(sprintf("Error: Dimensions of prior_network (%dx%d) must be %dx%d.", 
                     nrow(pred.net), ncol(pred.net), nrow(X), nrow(X)))
      }
    } else {
      message("Optional 'prior_network.csv' not found. Initializing a default fully-connected prior network (all 1s).")
      pred.net <- matrix(1, nrow = nrow(X), ncol = nrow(X))
      rownames(pred.net) <- rownames(X)
      colnames(pred.net) <- rownames(X)
    }
    
    # 4. Set algorithm parameters
    restK <- rep(ncol(X) - 1, nrow(X))
    topD <- round(0.6 * nrow(X))
    
    # 5. Estimate a single row of A using A.estimation.Srow
    # We estimate row 1 (r = 1) as specified in the documented workflow
    message("Estimating row 1 of the gene interaction matrix A...")
    result.Srow <- A.estimation.Srow(
      r = 1,
      cMM.corrected = 1,
      pred.net,
      X,
      P.known,
      topD,
      restK,
      cFlag = "ml",
      sup.drop = -1,
      noiseLevel = 0.1
    )
    
    # 6. Save the results to output files
    message("Saving results...")
    
    # Save the full result object as an RDS file
    saveRDS(result.Srow, file = "result_srow.rds")
    
    # Format and save the estimated row of A as a CSV table
    estimated_row_df <- data.frame(
      Target_Gene = rownames(X)[1],
      Regulator_Gene = rownames(X),
      Interaction_Weight = result.Srow\$A.row,
      stringsAsFactors = FALSE
    )
    write.csv(estimated_row_df, file = "estimated_A_row1.csv", row.names = FALSE)
    
    message("Workflow completed successfully. Outputs saved to 'result_srow.rds' and 'estimated_A_row1.csv'.")

    writeLines(c(
        '"BIOC_NTW_SINGLE_ROW_PREDICTION_KNOWN_P":',
        paste0('    NTW: ', as.character(packageVersion('NTW')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_row_prediction_known_p.csv versions.yml
    """
}

workflow BIOC_NTW_SINGLE_ROW_PREDICTION_KNOWN_P_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression.csv, known_perturbations.csv, prior_network.csv ] ]

    main:
    BIOC_NTW_SINGLE_ROW_PREDICTION_KNOWN_P(ch_input)

    emit:
    tables   = BIOC_NTW_SINGLE_ROW_PREDICTION_KNOWN_P.out.tables
    plots    = BIOC_NTW_SINGLE_ROW_PREDICTION_KNOWN_P.out.plots
    objects  = BIOC_NTW_SINGLE_ROW_PREDICTION_KNOWN_P.out.objects
    versions = BIOC_NTW_SINGLE_ROW_PREDICTION_KNOWN_P.out.versions
}
