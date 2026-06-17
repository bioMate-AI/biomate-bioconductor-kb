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
    
    # Load required libraries
    library(scuttle)
    library(SummarizedExperiment)
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
