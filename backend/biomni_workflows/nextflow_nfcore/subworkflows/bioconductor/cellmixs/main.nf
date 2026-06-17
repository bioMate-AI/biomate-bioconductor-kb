#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellMixS — quantify_and_visualize_batch_effects
// Quantify and visualize batch effects in unaligned single-cell RNA-seq data using the Cellspecific Mixing Score (CMS).
// Input: sce50
// Container: quay.io/biocontainers/bioconductor-cellmixs:1.26.0--r45hdfd78af_0
// R packages: SingleCellExperiment, CellMixS, cowplot, dplyr, ggplot2, magrittr, purrr
// Bioconductor: 3.20 | R: 4.4
// Requires: CellMixS, SingleCellExperiment, cowplot, dplyr, ggplot2, magrittr, purrr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Visualize batch distribution using visGroup
//  * 2. [Core Analysis] Calculate CMS using cms
//  * 3. [Visualization & Output] Visualize CMS results using visHist, visMetric, visOverview, and visCluster

nextflow.enable.dsl = 2

process BIOC_CELLMIXS_QUANTIFY_AND_VISUALIZE_BATCH_EFFECTS {
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
    .bm_deps <- c("SingleCellExperiment", "CellMixS", "cowplot", "dplyr", "ggplot2", "magrittr", "purrr", "SummarizedExperiment")
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
        
    # Load required packages
    suppressPackageStartupMessages({
      library(SummarizedExperiment)
      library(CellMixS)
      library(cowplot)
      library(ggplot2)
      library(dplyr)
      library(purrr)
      library(magrittr)
    })
    
    # 1. Read User Input
    # The pipeline reads the 'sce50' SingleCellExperiment object from the working directory.
    if (file.exists("sce50")) {
      sce50 <- readRDS("sce50")
    } else if (file.exists("sce50.rds")) {
      sce50 <- readRDS("sce50.rds")
    } else {
      stop("Error: Input file 'sce50' or 'sce50.rds' not found in the working directory.")
    }
    
    # 2. Visualize batch distribution using visGroup
    p_group_sce50 <- visGroup(sce50, group = "batch")
    
    # 3. Calculate CMS using cms
    sce50 <- cms(sce50, k = 30, group = "batch", res_name = "unaligned", n_dim = 3, cell_min = 4)
    
    # 4. Visualize CMS results using visHist, visMetric, visOverview, and visCluster
    p_hist_sce50 <- visHist(sce50)
    
    # Run the documented visualization functions on sce50
    metric_plot <- visMetric(sce50, metric_var = "cms_smooth.unaligned")
    group_plot <- visGroup(sce50, group = "batch")
    p_grid_sce50 <- plot_grid(metric_plot, group_plot, ncol = 2)
    
    p_overview_sce50 <- visOverview(sce50, "batch")
    p_cluster_sce50 <- visCluster(sce50, metric_var = "cms.unaligned", cluster_var = "batch")
    
    # 5. Write Outputs
    # Save all generated plots to a single PDF file
    pdf("batch_effects_plots.pdf", width = 11, height = 8.5)
    print(p_group_sce50)
    print(p_hist_sce50)
    print(p_grid_sce50)
    print(p_overview_sce50)
    print(p_cluster_sce50)
    dev.off()
    
    # Save the updated SingleCellExperiment object
    saveRDS(sce50, "sce50_cms_results.rds")
    
    # Save the colData containing the calculated CMS metrics as CSV tables
    write.csv(as.data.frame(colData(sce50)), "sce50_coldata_metrics.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CELLMIXS_QUANTIFY_AND_VISUALIZE_BATCH_EFFECTS":',
        paste0('    CellMixS: ', as.character(packageVersion('CellMixS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantify_and_visualize_batch_effects.csv versions.yml
    """
}

workflow BIOC_CELLMIXS_QUANTIFY_AND_VISUALIZE_BATCH_EFFECTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce50 ] ]

    main:
    BIOC_CELLMIXS_QUANTIFY_AND_VISUALIZE_BATCH_EFFECTS(ch_input)

    emit:
    tables   = BIOC_CELLMIXS_QUANTIFY_AND_VISUALIZE_BATCH_EFFECTS.out.tables
    plots    = BIOC_CELLMIXS_QUANTIFY_AND_VISUALIZE_BATCH_EFFECTS.out.plots
    objects  = BIOC_CELLMIXS_QUANTIFY_AND_VISUALIZE_BATCH_EFFECTS.out.objects
    versions = BIOC_CELLMIXS_QUANTIFY_AND_VISUALIZE_BATCH_EFFECTS.out.versions
}
