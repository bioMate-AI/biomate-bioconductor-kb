#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lpNet — time_series_network_inference
// Infer a signaling network from time-series perturbation data.
// Input: timeseries_expression.RData, perturbation_design.csv
// Container: quay.io/biocontainers/bioconductor-lpnet:2.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: lpNet
// Visualizations: heatmap, network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define network size, time points, and perturbation vector
//  * 2. [Core Analysis] Compute delta thresholds
//  * 3. [Core Analysis] Generate edge annotations using getEdgeAnnot
//  * 4. [Core Analysis] Run ILP network reconstruction with flag_time_series=TRUE using doILP
//  * 5. [Core Analysis] Convert the LP result to an adjacency matrix using getAdja

nextflow.enable.dsl = 2

process BIOC_LPNET_TIME_SERIES_NETWORK_INFERENCE {
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
    .bm_deps <- c("lpNet")
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
    library(lpNet)
    
    # 1. Load User Input Files
    if (!file.exists("timeseries_expression.RData")) {
      stop("Error: timeseries_expression.RData not found in the working directory.")
    }
    if (!file.exists("perturbation_design.csv")) {
      stop("Error: perturbation_design.csv not found in the working directory.")
    }
    
    # Load the 3D array of time-series measurements
    env <- new.env()
    load("timeseries_expression.RData", envir = env)
    var_names <- ls(env)
    
    obs_ts <- NULL
    for (v in var_names) {
      if (is.array(env[[v]]) && length(dim(env[[v]])) == 3) {
        obs_ts <- env[[v]]
        break
      }
    }
    
    if (is.null(obs_ts)) {
      # Fallback to the first object if no 3D array is explicitly identified by class
      obs_ts <- env[[var_names[1]]]
    }
    
    if (!is.array(obs_ts) || length(dim(obs_ts)) != 3) {
      stop("Error: Loaded object from timeseries_expression.RData is not a 3D array.")
    }
    
    # Define network size and time points from the loaded 3D array
    n <- dim(obs_ts)[1] # number of genes
    K <- dim(obs_ts)[2] # number of perturbation experiments
    T_ <- dim(obs_ts)[3] # number of time points
    
    # Load perturbation design matrix
    b_mat <- read.csv("perturbation_design.csv", row.names = 1, check.names = FALSE)
    b_mat <- as.matrix(b_mat)
    
    # Align perturbation matrix dimensions if necessary
    if (nrow(b_mat) != n || ncol(b_mat) != K) {
      if (nrow(b_mat) == K && ncol(b_mat) == n) {
        b_mat <- t(b_mat)
      } else {
        stop(sprintf("Error: Dimensions of perturbation_design.csv (%dx%d) do not match timeseries_expression.RData (%dx%d).", 
                     nrow(b_mat), ncol(b_mat), n, K))
      }
    }
    
    # Flatten to perturbation vector b (0 if gene inactivated and 1 otherwise)
    b <- as.vector(b_mat)
    
    # 2. Compute delta thresholds
    delta <- apply(obs_ts, 1, mean, na.rm = TRUE)
    delta_type <- "perGene"
    
    # 3. Generate edge annotations and run ILP network reconstruction
    # 4. Run ILP network reconstruction with flag_time_series=TRUE using doILP
    res1 <- doILP(obs_ts, delta, lambda=1, b, n, K, T_, 
                  annot=getEdgeAnnot(n), delta_type, 
                  flag_time_series=TRUE)
    
    # 5. Convert the LP result to an adjacency matrix using getAdja
    adja1 <- getAdja(res1, n)
    
    # Write named output files
    write.csv(adja1, file = "inferred_adjacency_matrix.csv", row.names = TRUE)
    saveRDS(res1, file = "ilp_result.rds")
    
    # Generate a PDF plot of the inferred adjacency matrix
    pdf("inferred_network_heatmap.pdf")
    heatmap(adja1, Rowv = NA, Colv = NA, col = heat.colors(256), scale = "none",
            margins = c(5, 5), main = "Inferred Network Adjacency Matrix")
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to 'inferred_adjacency_matrix.csv', 'ilp_result.rds', and 'inferred_network_heatmap.pdf'.\n")

    writeLines(c(
        '"BIOC_LPNET_TIME_SERIES_NETWORK_INFERENCE":',
        paste0('    lpNet: ', as.character(packageVersion('lpNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_series_network_inference.csv versions.yml
    """
}

workflow BIOC_LPNET_TIME_SERIES_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ timeseries_expression.RData, perturbation_design.csv ] ]

    main:
    BIOC_LPNET_TIME_SERIES_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_LPNET_TIME_SERIES_NETWORK_INFERENCE.out.tables
    plots    = BIOC_LPNET_TIME_SERIES_NETWORK_INFERENCE.out.plots
    objects  = BIOC_LPNET_TIME_SERIES_NETWORK_INFERENCE.out.objects
    versions = BIOC_LPNET_TIME_SERIES_NETWORK_INFERENCE.out.versions
}
