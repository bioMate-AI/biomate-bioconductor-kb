#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AMOUNTAIN — multi_layer_module_detection
// Identify active gene modules across multiple network layers sharing a common network structure.
// Input: W, listz
// Container: quay.io/biocontainers/bioconductor-amountain:1.36.0--r45h57f0213_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AMOUNTAIN
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Organize the node scores for each layer into a list
//  * 2. [Core Analysis] Run moduleIdentificationGPFixSSMultilayer using the shared network and the list of node scores
//  * 3. [Core Analysis] Extract the predicted module member indices

nextflow.enable.dsl = 2

process BIOC_AMOUNTAIN_MULTI_LAYER_MODULE_DETECTION {
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
    .bm_deps <- c("AMOUNTAIN")
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
    
    # Load required library
    library(AMOUNTAIN)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Read the shared edge weight matrix (W)
    if (file.exists("W.rds")) {
      W <- readRDS("W.rds")
    } else if (file.exists("W.csv")) {
      W <- as.matrix(read.csv("W.csv", header = FALSE))
    } else {
      stop("Error: Shared edge weight matrix file ('W.csv' or 'W.rds') not found in the working directory.")
    }
    
    # Read the list of node score vectors (listz)
    if (file.exists("listz.rds")) {
      listz <- readRDS("listz.rds")
    } else if (file.exists("listz.csv")) {
      df_z <- read.csv("listz.csv", header = FALSE)
      # Convert columns of the data frame into a list of numeric vectors
      listz <- lapply(seq_len(ncol(df_z)), function(i) as.numeric(df_z[[i]]))
    } else {
      stop("Error: Node score vectors file ('listz.csv' or 'listz.rds') not found in the working directory.")
    }
    
    # Validate inputs
    n <- nrow(W)
    if (ncol(W) != n) {
      stop("Error: Edge weight matrix W must be a square matrix.")
    }
    
    for (i in seq_along(listz)) {
      if (length(listz[[i]]) != n) {
        stop(paste0("Error: Node score vector at index ", i, " does not match the number of nodes (", n, ")."))
      }
    }
    
    # -----------------------------------------------------------------------------
    # 2. Run Module Identification
    # -----------------------------------------------------------------------------
    
    # Run the multi-layer module detection using the documented function
    # W represents the shared network (cpl[[1]] in the vignette)
    # listz represents the list of node scores for each layer
    # rep(1/n, n) is the initial starting vector
    x <- moduleIdentificationGPFixSSMultilayer(W, listz, rep(1/n, n))
    
    # Extract the predicted module member indices
    predictedid <- which(x[[2]] != 0)
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    
    # Save the predicted module indices to a CSV file
    write.csv(data.frame(Module_Member_Index = predictedid), 
              file = "predicted_module_indices.csv", 
              row.names = FALSE)
    
    # Save the continuous membership vector (x[[2]]) to a CSV file
    write.csv(data.frame(Node_Index = 1:n, Membership_Weight = x[[2]]), 
              file = "module_membership_weights.csv", 
              row.names = FALSE)
    
    # Save the complete result object as an RDS file
    saveRDS(x, file = "multilayer_module_result.rds")
    
    # Optional: Generate a simple diagnostic plot of the membership weights
    pdf("module_membership_plot.pdf", width = 7, height = 5)
    plot(x[[2]], type = "h", main = "Module Membership Weights",
         xlab = "Node Index", ylab = "Weight", col = "blue", lwd = 2)
    abline(h = 0, col = "gray")
    dev.off()

    writeLines(c(
        '"BIOC_AMOUNTAIN_MULTI_LAYER_MODULE_DETECTION":',
        paste0('    AMOUNTAIN: ', as.character(packageVersion('AMOUNTAIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_layer_module_detection.csv versions.yml
    """
}

workflow BIOC_AMOUNTAIN_MULTI_LAYER_MODULE_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ W, listz ] ]

    main:
    BIOC_AMOUNTAIN_MULTI_LAYER_MODULE_DETECTION(ch_input)

    emit:
    tables   = BIOC_AMOUNTAIN_MULTI_LAYER_MODULE_DETECTION.out.tables
    plots    = BIOC_AMOUNTAIN_MULTI_LAYER_MODULE_DETECTION.out.plots
    objects  = BIOC_AMOUNTAIN_MULTI_LAYER_MODULE_DETECTION.out.objects
    versions = BIOC_AMOUNTAIN_MULTI_LAYER_MODULE_DETECTION.out.versions
}
