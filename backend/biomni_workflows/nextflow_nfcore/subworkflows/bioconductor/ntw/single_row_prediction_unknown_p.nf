#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NTW — single_row_prediction_unknown_p
// Estimate a single row of the gene interaction matrix (A) and the perturbation targets matrix (P) when the perturbation matrix is unknown (useful for parallelizi
// Input: gene_expression.csv, prior_network.csv
// Container: quay.io/biocontainers/bioconductor-ntw:1.60.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: NTW, mvtnorm
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the gene expression data and convert to a matrix
//  * 2. [Core Analysis] Set algorithm parameters (restK, topD, topK, numP)
//  * 3. [Core Analysis] Pre-estimate the perturbation matrix using P.preestimation
//  * 4. [Core Analysis] Estimate a single row of A and P using AP.estimation.Srow

nextflow.enable.dsl = 2

process BIOC_NTW_SINGLE_ROW_PREDICTION_UNKNOWN_P {
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
      stop("Error: gene_expression.csv not found in the working directory.")
    }
    X <- as.matrix(read.csv("gene_expression.csv", row.names = 1, check.names = FALSE))
    
    # Load prior network if available, otherwise set to NULL
    if (file.exists("prior_network.csv")) {
      pred.net <- as.matrix(read.csv("prior_network.csv", row.names = 1, check.names = FALSE))
    } else {
      pred.net <- NULL
    }
    
    # 2. Set algorithm parameters
    restK <- rep(ncol(X) - 1, nrow(X))
    topD <- round(0.6 * nrow(X))
    topK <- round(0.5 * nrow(X))
    numP <- round(0.25 * nrow(X))
    
    # 3. Pre-estimate the perturbation matrix using P.preestimation
    IX <- P.preestimation(X, topK = round(2 * nrow(X)))
    
    # 4. Estimate a single row of A and P using AP.estimation.Srow
    # cMM.corrected must be 1 if pred.net is provided, and 0 if pred.net is NULL
    cMM_corrected <- if (is.null(pred.net)) 0 else 1
    result.Srow <- AP.estimation.Srow(r = 1, cMM.corrected = cMM_corrected, pred.net, X, IX, topD, restK, cFlag = "sse", sup.drop = -1, numP, noiseLevel = 0.1)
    
    # Save outputs
    saveRDS(result.Srow, "result_Srow.rds")
    
    # Export A.row and P.index to CSV
    A_row_df <- data.frame(Gene = rownames(X), Coefficient = result.Srow\$A.row)
    write.csv(A_row_df, "estimated_A_row1.csv", row.names = FALSE)
    
    P_index_df <- data.frame(Perturbed_Experiment_Index = result.Srow\$P.index)
    write.csv(P_index_df, "estimated_P_index_row1.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_NTW_SINGLE_ROW_PREDICTION_UNKNOWN_P":',
        paste0('    NTW: ', as.character(packageVersion('NTW')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_row_prediction_unknown_p.csv versions.yml
    """
}

workflow BIOC_NTW_SINGLE_ROW_PREDICTION_UNKNOWN_P_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression.csv, prior_network.csv ] ]

    main:
    BIOC_NTW_SINGLE_ROW_PREDICTION_UNKNOWN_P(ch_input)

    emit:
    tables   = BIOC_NTW_SINGLE_ROW_PREDICTION_UNKNOWN_P.out.tables
    plots    = BIOC_NTW_SINGLE_ROW_PREDICTION_UNKNOWN_P.out.plots
    objects  = BIOC_NTW_SINGLE_ROW_PREDICTION_UNKNOWN_P.out.objects
    versions = BIOC_NTW_SINGLE_ROW_PREDICTION_UNKNOWN_P.out.versions
}
