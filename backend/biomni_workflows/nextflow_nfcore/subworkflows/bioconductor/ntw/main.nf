#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NTW — network_and_perturbation_prediction
// Estimate the entire gene interaction network (A) and the perturbation targets matrix (P) from gene expression data, with or without prior network knowledge.
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
//  * 3. [Input & Preparation] Define or generate a prior network matrix (optional)
//  * 4. [Core Analysis] Run the main NTW function to estimate the interaction network and perturbation targets

nextflow.enable.dsl = 2

process BIOC_NTW_NETWORK_AND_PERTURBATION_PREDICTION {
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
    
    X <- read.csv("gene_expression.csv", row.names = 1, check.names = FALSE)
    X <- as.matrix(X)
    
    # 2. Set algorithm parameters
    restK = rep(ncol(X) - 1, nrow(X))
    topD = round(0.6 * nrow(X))
    topK = round(0.5 * nrow(X))
    numP = round(0.25 * nrow(X))
    
    # 3. Run the main NTW function to estimate the interaction network and perturbation targets
    # Stage 3a: Estimation without prior network knowledge
    result <- NTW(X, restK, topD, topK, P.known=NULL, cFlag="sse", pred.net = NULL, sup.drop = -1, numP, noiseLevel=0.1)
    
    # Save results without prior
    write.csv(result\$est.A, "estimated_A_no_prior.csv", row.names = TRUE)
    write.csv(result\$est.P, "estimated_P_no_prior.csv", row.names = TRUE)
    saveRDS(result, "ntw_result_no_prior.rds")
    
    # Stage 3b: Estimation with prior network knowledge (if optional file is provided)
    if (file.exists("prior_network.csv")) {
      pred.net <- read.csv("prior_network.csv", row.names = 1, check.names = FALSE)
      pred.net <- as.matrix(pred.net)
      
      result <- NTW(X, restK, topD, topK, P.known=NULL, cFlag="sse", pred.net = pred.net, sup.drop = 1, numP, noiseLevel=0.1)
      
      # Save results with prior
      write.csv(result\$est.A, "estimated_A_with_prior.csv", row.names = TRUE)
      write.csv(result\$est.P, "estimated_P_with_prior.csv", row.names = TRUE)
      saveRDS(result, "ntw_result_with_prior.rds")
    }

    writeLines(c(
        '"BIOC_NTW_NETWORK_AND_PERTURBATION_PREDICTION":',
        paste0('    NTW: ', as.character(packageVersion('NTW')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_and_perturbation_prediction.csv versions.yml
    """
}

workflow BIOC_NTW_NETWORK_AND_PERTURBATION_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression.csv, prior_network.csv ] ]

    main:
    BIOC_NTW_NETWORK_AND_PERTURBATION_PREDICTION(ch_input)

    emit:
    tables   = BIOC_NTW_NETWORK_AND_PERTURBATION_PREDICTION.out.tables
    plots    = BIOC_NTW_NETWORK_AND_PERTURBATION_PREDICTION.out.plots
    objects  = BIOC_NTW_NETWORK_AND_PERTURBATION_PREDICTION.out.objects
    versions = BIOC_NTW_NETWORK_AND_PERTURBATION_PREDICTION.out.versions
}
