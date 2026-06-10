#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEhex
// This package provides panels summarising data points in hexagonal bins for `iSEE`. It is part of `iS
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEhex/inst/doc/iSEEhex.R
// Upstream  : BiocStyle, scRNAseq, scater
// Downstream: iSEEu
//
// Install: BiocManager::install("iSEEhex")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ISEEHEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseehex"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_iseehex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseehex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseehex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iSEEhex)
    library(ReducedDimensionHexPlot)
    library(ReducedDimensionPlot)
    library(ReprocessedAllenData)
    library(jsonlite)

    # --- Single-Cell Data Preparation [] ---
    # Key functions: ReprocessedAllenData, logNormCounts, runPCA, runTSNE
    sce <- scRNAseq::ReprocessedAllenData(assays = "tophat_counts")
    sce <- scater::logNormCounts(sce, exprs_values = "tophat_counts")
    sce <- scater::runPCA(sce, ncomponents = 4)
    sce <- scater::runTSNE(sce)
    SummarizedExperiment::rowData(sce)\$ave_count <- rowMeans(
        SummarizedExperiment::assay(sce, "tophat_counts")
    )
    SummarizedExperiment::rowData(sce)\$n_cells <- rowSums(
        SummarizedExperiment::assay(sce, "tophat_counts") > 0
    )

    # --- Hexagonal Panel Configuration [] ---
    # Key functions: ReducedDimensionHexPlot, ColumnDataHexPlot
    hex_red_dim <- iSEEhex::ReducedDimensionHexPlot(
        ColorBy = "Feature name",
        ColorByFeatureName = "Cux2",
        PanelWidth = 6L,
        BinResolution = 30
    )
    hex_col_data <- iSEEhex::ColumnDataHexPlot(
        PanelWidth = 6L,
        BinResolution = 25
    )
    initial_panels <- list(hex_red_dim, hex_col_data)

    # --- Interactive Visualization App Creation [] ---
    # Key functions: iSEE
    app <- iSEE::iSEE(
        se = sce,
        initial = initial_panels
    )


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_iseehex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_iseehex_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_iseehex_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEHEX:", paste0("    iseehex: ", as.character(packageVersion("iSEEhex")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseehex_results.csv
    touch ${prefix}_iseehex_output.rds
    echo "BIOC_ISEEHEX:" > versions.yml
    echo "    iseehex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEHEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_ISEEHEX(ch_input)

    emit:
    results  = BIOC_ISEEHEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEHEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEHEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEHEX.out.versions  // channel: path(versions.yml)
}
