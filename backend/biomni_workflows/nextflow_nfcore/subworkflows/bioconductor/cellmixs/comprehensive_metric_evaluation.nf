#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellMixS — comprehensive_metric_evaluation
// Run a suite of different integration metrics (e.g., inverse Simpson index, entropy) simultaneously using a wrapper function.
// Input: sce50
// Container: quay.io/biocontainers/bioconductor-cellmixs:1.26.0--r45hdfd78af_0
// R packages: CellMixS, SingleCellExperiment, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: CellMixS, SingleCellExperiment, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run multiple metrics using evalIntegration
//  * 2. [Visualization & Output] Visualize the overview of all metrics using visOverview

nextflow.enable.dsl = 2

process BIOC_CELLMIXS_COMPREHENSIVE_METRIC_EVALUATION {
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
    .bm_deps <- c("CellMixS", "SingleCellExperiment", "ggplot2", "SummarizedExperiment")
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
    suppressPackageStartupMessages({
          library(SummarizedExperiment)
      library(CellMixS)
        library(ggplot2)
    })
    
    # 1. Read user input
    if (file.exists("sce50.rds")) {
        sce50 <- readRDS("sce50.rds")
    } else if (file.exists("sce50")) {
        sce50 <- readRDS("sce50")
    } else {
        stop("Input file 'sce50.rds' or 'sce50' not found in the working directory.")
    }
    
    # Ensure cms_smooth.unaligned is present in colData to satisfy the visOverview requirements
    if (!"cms_smooth.unaligned" %in% colnames(colData(sce50))) {
        sce50 <- cms(sce50, k = 30, group = "batch", res_name = "unaligned", n_dim = 3, cell_min = 4)
    }
    
    # 2. Run multiple metrics using evalIntegration
    sce50 <- evalIntegration(metrics = c("isi", "entropy"), sce50, group = "batch", k = 30, n_dim = 2, cell_min = 4, res_name = c("weighted_isi", "entropy"))
    
    # 3. Visualize the overview of all metrics using visOverview
    overview_plot <- visOverview(sce50, "batch", metric = c("cms_smooth.unaligned", "weighted_isi", "entropy"), prefix = FALSE)
    
    # 4. Save outputs
    # Save the updated SingleCellExperiment object
    saveRDS(sce50, "sce50_evaluated.rds")
    
    # Save the colData containing the metrics as a CSV
    write.csv(as.data.frame(colData(sce50)), "metric_evaluation_results.csv", row.names = TRUE)
    
    # Save the visualization plot
    ggsave("vis_overview.pdf", plot = overview_plot, width = 10, height = 8)
    ggsave("vis_overview.png", plot = overview_plot, width = 10, height = 8, dpi = 300)

    writeLines(c(
        '"BIOC_CELLMIXS_COMPREHENSIVE_METRIC_EVALUATION":',
        paste0('    CellMixS: ', as.character(packageVersion('CellMixS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comprehensive_metric_evaluation.csv versions.yml
    """
}

workflow BIOC_CELLMIXS_COMPREHENSIVE_METRIC_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce50 ] ]

    main:
    BIOC_CELLMIXS_COMPREHENSIVE_METRIC_EVALUATION(ch_input)

    emit:
    tables   = BIOC_CELLMIXS_COMPREHENSIVE_METRIC_EVALUATION.out.tables
    plots    = BIOC_CELLMIXS_COMPREHENSIVE_METRIC_EVALUATION.out.plots
    objects  = BIOC_CELLMIXS_COMPREHENSIVE_METRIC_EVALUATION.out.objects
    versions = BIOC_CELLMIXS_COMPREHENSIVE_METRIC_EVALUATION.out.versions
}
