#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diffuStats — grid_diffusion_and_benchmarking
// Precompute a graph kernel, run multiple diffusion methods in parallel, and evaluate their performance against validation labels.
// Input: network.graph, training_labels.csv, validation_labels.csv
// Container: quay.io/biocontainers/bioconductor-diffustats:1.30.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: diffuStats, ggplot2, ggsci, igraph, reshape2
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Precompute the Regularised Laplacian Kernel
//  * 3. [Core Analysis] Run Diffusion Across a Grid of Methods
//  * 4. [Core Analysis] Evaluate Performance of Multiple Methods
//  * 5. [Core Analysis] Statistically Compare Performance Metrics
//  * 6. [Core Analysis] Save Outputs

nextflow.enable.dsl = 2

process BIOC_DIFFUSTATS_GRID_DIFFUSION_AND_BENCHMARKING {
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
    .bm_deps <- c("igraph", "diffuStats", "reshape2", "ggplot2", "ggsci")
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
    library(igraph)
    library(diffuStats)
    library(reshape2)
    library(ggplot2)
    library(ggsci)
    
    # -----------------------------------------------------------------------------
    # --- Read User Input Files ---
    # -----------------------------------------------------------------------------
    # Read the igraph network object
    yeast <- readRDS("network.graph")
    
    # Read training labels (matrix of known node labels for training)
    training_df <- read.csv("training_labels.csv", row.names = 1, check.names = FALSE)
    mat_training <- as.matrix(training_df)
    
    # Read validation labels (matrix of target node labels for validation)
    validation_df <- read.csv("validation_labels.csv", row.names = 1, check.names = FALSE)
    mat_validation <- as.matrix(validation_df)
    
    # Extract scores_A as a named vector from the first column of training labels
    scores_A <- mat_training[, 1]
    
    # Define the list of diffusion methods to evaluate
    list_methods <- c("raw", "ml", "gm", "ber_s", "ber_p", "mc", "z")
    
    # -----------------------------------------------------------------------------
    # --- Precompute the Regularised Laplacian Kernel ---
    # -----------------------------------------------------------------------------
    K_rl <- diffuStats::regularisedLaplacianKernel(yeast)
    
    # -----------------------------------------------------------------------------
    # --- Run Diffusion Across a Grid of Methods ---
    # -----------------------------------------------------------------------------
    df_diff <- diffuse_grid(
        K = K_rl,
        scores = scores_A,
        grid_param = expand.grid(method = list_methods),
        n.perm = 1000 
    )
    
    # -----------------------------------------------------------------------------
    # --- Evaluate Performance of Multiple Methods ---
    # -----------------------------------------------------------------------------
    df_methods <- perf(
        K = K_rl,
        scores = mat_training,
        validation = mat_validation,
        grid_param = expand.grid(
            method = list_methods,
            stringsAsFactors = FALSE),
        n.perm = 1000
    )
    
    # Format the performance data
    df_perf <- reshape2::acast(df_methods, Column~method, value.var = "auc")
    
    # -----------------------------------------------------------------------------
    # --- Statistically Compare Performance Metrics ---
    # -----------------------------------------------------------------------------
    df_test <- perf_wilcox(
        df_perf, 
        digits_p = 1, 
        adjust = function(p) p.adjust(p, method = "fdr"), 
        scientific = FALSE)
    
    # -----------------------------------------------------------------------------
    # --- Save Outputs ---
    # -----------------------------------------------------------------------------
    # Save tabular results
    write.csv(df_diff, "diffusion_grid_scores.csv", row.names = FALSE)
    write.csv(df_methods, "performance_metrics.csv", row.names = FALSE)
    write.csv(df_perf, "performance_auc_matrix.csv", row.names = TRUE)
    write.csv(df_test, "wilcoxon_test_results.csv", row.names = TRUE)
    
    # Save performance boxplot
    tryCatch({
        p <- ggplot(df_methods, aes(x = method, y = auc)) +
            geom_boxplot(aes(fill = method)) +
            scale_fill_npg() +
            theme_bw() +
            xlab("Method") +
            ylab("Area under the curve") +
            ggtitle("Methods performance in all categories")
        ggsave("performance_boxplot.pdf", plot = p, width = 7, height = 6)
    }, error = function(e) {
        warning("Plotting failed, but data outputs were successfully written: ", e\$message)
    })

    writeLines(c(
        '"BIOC_DIFFUSTATS_GRID_DIFFUSION_AND_BENCHMARKING":',
        paste0('    diffuStats: ', as.character(packageVersion('diffuStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grid_diffusion_and_benchmarking.csv versions.yml
    """
}

workflow BIOC_DIFFUSTATS_GRID_DIFFUSION_AND_BENCHMARKING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network.graph, training_labels.csv, validation_labels.csv ] ]

    main:
    BIOC_DIFFUSTATS_GRID_DIFFUSION_AND_BENCHMARKING(ch_input)

    emit:
    tables   = BIOC_DIFFUSTATS_GRID_DIFFUSION_AND_BENCHMARKING.out.tables
    plots    = BIOC_DIFFUSTATS_GRID_DIFFUSION_AND_BENCHMARKING.out.plots
    objects  = BIOC_DIFFUSTATS_GRID_DIFFUSION_AND_BENCHMARKING.out.objects
    versions = BIOC_DIFFUSTATS_GRID_DIFFUSION_AND_BENCHMARKING.out.versions
}
