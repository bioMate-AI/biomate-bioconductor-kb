#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDataviz — import_from_seurat
// Convert a Seurat object to SingleCellExperiment and perform marker expression and enrichment analysis.
// Input: pbmc
// Container: quay.io/biocontainers/bioconductor-scdataviz:1.20.0--r45hdfd78af_0
// R packages: Seurat, SingleCellExperiment, ggplot2, scDataviz
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, SingleCellExperiment, ggplot2, scDataviz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the user-provided Seurat object from the working
//  * 2. [Visualization & Output] Convert Seurat object to SingleCellExperiment
//  * 3. [Visualization & Output] Manually assign the metadata slot
//  * 4. [Visualization & Output] Plot marker expression using markerExpression with custom
//  * 5. [Visualization & Output] Perform marker enrichment using markerEnrichment

nextflow.enable.dsl = 2

process BIOC_SCDATAVIZ_IMPORT_FROM_SEURAT {
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
    .bm_deps <- c("Seurat", "SingleCellExperiment", "ggplot2", "scDataviz", "SummarizedExperiment")
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
    library(scDataviz)
    library(SummarizedExperiment)
    library(Seurat)
    library(ggplot2)
    
    # --- Read the user-provided Seurat object from the working ---
    if (file.exists("pbmc")) {
      pbmc <- readRDS("pbmc")
    } else if (file.exists("pbmc.rds")) {
      pbmc <- readRDS("pbmc.rds")
    } else {
      stop("Required input file 'pbmc' or 'pbmc.rds' not found in the working directory.")
    }
    
    # --- Convert Seurat object to SingleCellExperiment ---
    sce <- as.SingleCellExperiment(pbmc)
    
    # --- Manually assign the metadata slot ---
    metadata(sce) <- data.frame(colData(sce))
    
    # --- Plot marker expression using markerExpression with custom ---
    p_expr <- markerExpression(sce,
      assay = 'logcounts',
      reducedDim = 'UMAP',
      dimColnames = c('UMAP_1','UMAP_2'),
      markers = c('CD79A', 'Cd79B', 'MS4A1'))
    
    # Save the marker expression plot
    ggsave("marker_expression_plot.pdf", plot = p_expr, width = 12, height = 4, device = "pdf")
    
    # --- Perform marker enrichment using markerEnrichment ---
    enrich_res <- markerEnrichment(sce,
      assay = 'logcounts',
      method = 'quantile',
      sampleAbundances = TRUE,
      sampleID = 'orig.ident',
      studyvarID = 'ident',
      clusterAssign = as.character(colData(sce)[['seurat_clusters']]))
    
    # Save the enrichment results table
    write.csv(enrich_res, "marker_enrichment_results.csv", row.names = FALSE)
    
    # Save the converted SingleCellExperiment object
    saveRDS(sce, "sce_converted.rds")

    writeLines(c(
        '"BIOC_SCDATAVIZ_IMPORT_FROM_SEURAT":',
        paste0('    scDataviz: ', as.character(packageVersion('scDataviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_from_seurat.csv versions.yml
    """
}

workflow BIOC_SCDATAVIZ_IMPORT_FROM_SEURAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc ] ]

    main:
    BIOC_SCDATAVIZ_IMPORT_FROM_SEURAT(ch_input)

    emit:
    tables   = BIOC_SCDATAVIZ_IMPORT_FROM_SEURAT.out.tables
    plots    = BIOC_SCDATAVIZ_IMPORT_FROM_SEURAT.out.plots
    objects  = BIOC_SCDATAVIZ_IMPORT_FROM_SEURAT.out.objects
    versions = BIOC_SCDATAVIZ_IMPORT_FROM_SEURAT.out.versions
}
