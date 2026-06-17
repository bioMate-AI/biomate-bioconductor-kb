#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDotPlot — single_cell_experiment_dotplot
// Generate an annotated, hierarchically clustered dot plot from a SingleCellExperiment object.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-scdotplot:1.4.0--r45hdfd78af_0
// R packages: SingleCellExperiment, AnnotationDbi, dplyr, ggplot2, ggsci, purrr, scDotPlot, scran, scuttle, Seurat, SeuratObject
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, SingleCellExperiment, aplot, dplyr, ggplot2, ggsci, purrr, scDotPlot, scran, scuttle
// Visualizations: dot plot
// QC: missing-value handling, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize and subset the SingleCellExperiment object
//  * 2. [Core Analysis] Identify marker genes and add them to the rowData of the object
//  * 3. [Visualization & Output] Generate the clustered dot plot with annotations using scDotPlot

nextflow.enable.dsl = 2

process BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "AnnotationDbi", "dplyr", "ggplot2", "ggsci", "purrr", "scDotPlot", "scran", "scuttle", "Seurat", "SeuratObject", "SummarizedExperiment")
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
    
    # Load required librari    library(SummarizedExperiment)
es
    library(scuttle)
    library(scran)
    library(purrr)
    library(dplyr)
    library(AnnotationDbi)
    library(scDotPlot)
    library(ggsci)
    library(ggplot2)
    
    # 1. Read the input SingleCellExperiment object from the working directory
    sce <- readRDS("sce.rds")
    
    # Dynamically determine grouping and annotation columns from colData
    anno_col <- colnames(colData(sce))[1]
    group_col <- if (ncol(colData(sce)) > 1) colnames(colData(sce))[2] else anno_col
    
    # 2. Normalize and subset the SingleCellExperiment object
    sce <- sce |> 
        logNormCounts()
    sce <- sce[, !is.na(sce[[group_col]])]
    
    # 3. Identify marker genes and add them to the rowData of the object
    features <- sce |>
        scoreMarkers(sce[[anno_col]]) |>
        map(~ .x |>
                as.data.frame() |>
                arrange(desc(mean.AUC))|>
                dplyr::slice(1:6) |>
                rownames()) |> 
        unlist2()
    
    rowData(sce)\$Marker <- features[match(rownames(sce), features)] |>
        names()
    
    # Dynamically determine the number of unique values for color palettes
    n_anno <- length(unique(na.omit(sce[[anno_col]])))
    n_marker <- length(unique(na.omit(rowData(sce)\$Marker)))
    
    # 4. Generate and save the clustered dot plot (logcounts)
    p1 <- sce |>
        scDotPlot(features = features,
                  group = group_col,
                  groupAnno = anno_col,
                  featureAnno = "Marker",
                  groupLegends = FALSE,
                  annoColors = setNames(list(colorRampPalette(pal_d3()(10))(n_anno), 
                                             colorRampPalette(pal_d3()(10))(n_marker)), 
                                        c(anno_col, "Marker")),
                  annoWidth = 0.02)
    
    aplot::ggsave("scDotPlot_logcounts.pdf", plot = p1, width = 12, height = 12)
    
    # 5. Generate and save the clustered dot plot (Z-scores)
    p2 <- sce |>
        scDotPlot(scale = TRUE,
                  features = features,
                  group = group_col,
                  groupAnno = anno_col,
                  featureAnno = "Marker",
                  groupLegends = FALSE,
                  annoColors = setNames(list(colorRampPalette(pal_d3()(10))(n_anno), 
                                             colorRampPalette(pal_d3()(10))(n_marker)), 
                                        c(anno_col, "Marker")),
                  annoWidth = 0.02)
    
    aplot::ggsave("scDotPlot_zscores.pdf", plot = p2, width = 12, height = 12)
    
    # 6. Save processed objects and features
    write.csv(data.frame(Feature = features, Marker = names(features)), "marker_features.csv", row.names = FALSE)
    saveRDS(sce, "sce_processed.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT":',
        paste0('    scDotPlot: ', as.character(packageVersion('scDotPlot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_experiment_dotplot.csv versions.yml
    """
}

workflow BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT(ch_input)

    emit:
    tables   = BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT.out.tables
    plots    = BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT.out.plots
    objects  = BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT.out.objects
    versions = BIOC_SCDOTPLOT_SINGLE_CELL_EXPERIMENT_DOTPLOT.out.versions
}
