#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellMixS — evaluate_and_compare_integration
// Evaluate and compare different batch correction/integration methods by assessing both cell mixing (CMS) and preservation of local structure (ldfDiff).
// Input: sce20, sce_pre_list
// Container: quay.io/biocontainers/bioconductor-cellmixs:1.26.0--r45hdfd78af_0
// R packages: CellMixS, SingleCellExperiment, cowplot, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: CellMixS, SingleCellExperiment, cowplot, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run cms on integrated embeddings (e.g., MNN) or corrected assays (e.g., limma)
//  * 2. [Core Analysis] Compare mixing using visHist
//  * 3. [Core Analysis] Calculate local density differences before and after integration using ldfDiff
//  * 4. [Visualization & Output] Visualize structure preservation using visIntegration

nextflow.enable.dsl = 2

process BIOC_CELLMIXS_EVALUATE_AND_COMPARE_INTEGRATION {
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
    .bm_deps <- c("CellMixS", "SingleCellExperiment", "cowplot", "ggplot2", "SummarizedExperiment")
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
    
    # Load required librarie    library(SummarizedExperiment)
s
    library(CellMixS)
    library(ggplot2)
    library(cowplot)
    
    # 1. Read user input files from the working directory
    if (!file.exists("sce20.rds") || !file.exists("sce_pre_list.rds")) {
      stop("Required input files 'sce20.rds' and/or 'sce_pre_list.rds' are missing in the working directory.")
    }
    
    sce20 <- readRDS("sce20.rds")
    sce_pre_list <- readRDS("sce_pre_list.rds")
    
    # 2. Run cms on integrated embeddings (MNN) and corrected assays (limma)
    sce20 <- cms(sce20, k = 30, group = "batch", dim_red = "MNN", res_name = "MNN", n_dim = 3, cell_min = 4)
    sce20 <- cms(sce20, k = 30, group = "batch", assay_name = "lim_corrected", res_name = "limma", n_dim = 3, cell_min = 4)
    
    # 3. Compare mixing using visHist and save the plot
    p_hist <- visHist(sce20, metric = "cms.",  n_col = 3)
    ggsave("visHist_cms_comparison.pdf", plot = p_hist, width = 10, height = 4)
    
    # 4. Calculate local density differences before and after integration using ldfDiff
    sce20 <- ldfDiff(sce_pre_list, sce_combined = sce20, group = "batch", k = 70, dim_red = "PCA", dim_combined = "MNN", assay_pre = "counts", n_dim = 3, res_name = "MNN")
    sce20 <- ldfDiff(sce_pre_list, sce_combined = sce20, group = "batch", k = 70, dim_red = "PCA", dim_combined = "PCA", assay_pre = "counts", assay_combined = "lim_corrected", n_dim = 3, res_name = "limma")
    
    # 5. Visualize structure preservation using visIntegration and save the plot
    p_integration <- visIntegration(sce20, metric = "diff_ldf", metric_name = "ldfDiff")
    ggsave("visIntegration_ldfDiff.pdf", plot = p_integration, width = 8, height = 6)
    
    # 6. Save the evaluated SingleCellExperiment object and its metadata
    saveRDS(sce20, "sce20_evaluated.rds")
    write.csv(as.data.frame(colData(sce20)), "sce20_evaluated_metadata.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CELLMIXS_EVALUATE_AND_COMPARE_INTEGRATION":',
        paste0('    CellMixS: ', as.character(packageVersion('CellMixS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_evaluate_and_compare_integration.csv versions.yml
    """
}

workflow BIOC_CELLMIXS_EVALUATE_AND_COMPARE_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce20, sce_pre_list ] ]

    main:
    BIOC_CELLMIXS_EVALUATE_AND_COMPARE_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_CELLMIXS_EVALUATE_AND_COMPARE_INTEGRATION.out.tables
    plots    = BIOC_CELLMIXS_EVALUATE_AND_COMPARE_INTEGRATION.out.plots
    objects  = BIOC_CELLMIXS_EVALUATE_AND_COMPARE_INTEGRATION.out.objects
    versions = BIOC_CELLMIXS_EVALUATE_AND_COMPARE_INTEGRATION.out.versions
}
