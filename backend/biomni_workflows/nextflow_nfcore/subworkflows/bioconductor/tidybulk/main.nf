#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidybulk
// This is a collection of utility functions that allow to perform exploration of and calculations to R
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidybulk/inst/doc/introduction.R
// Upstream  : Seurat, edgeR, limma, sva, widyr
// Downstream: none
//
// Install: BiocManager::install("tidybulk")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TIDYBULK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidybulk"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidybulk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidybulk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidybulk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidybulk)
    library(DGEList)
    library(jsonlite)

    # --- Duplicate Aggregation [] ---
    # Key functions: tidybulk, aggregate_duplicates
    rowData(tidybulk::se_mini)\$gene_name <- rownames(tidybulk::se_mini)
    se_mini.aggr <- tidybulk::se_mini |>
        tidybulk() |>
        aggregate_duplicates(.transcript = gene_name)

    # --- Abundance Normalisation [] ---
    # Key functions: identify_abundant, scale_abundance
    se_mini.norm <- se_mini.aggr |>
        identify_abundant(factor_of_interest = condition) |>
        scale_abundance()

    # --- Dimensionality Reduction [] ---
    # Key functions: keep_variable, reduce_dimensions
    se_mini.norm.variable <- se_mini.norm |>
        keep_variable()
    se_mini.norm.MDS <- se_mini.norm.variable |>
        reduce_dimensions(method = "MDS", .dims = 3)
    se_mini.norm.PCA <- se_mini.norm.variable |>
        reduce_dimensions(method = "PCA", .dims = 3)

    # --- Differential Abundance Analysis [] ---
    # Key functions: test_differential_abundance
    se_mini.de <- se_mini.aggr |>
        test_differential_abundance(~ condition, action = "get")

    # --- Batch Effect Adjustment [] ---
    # Key functions: adjust_abundance
    se_mini.adj <- se_mini.norm |>
        adjust_abundance(
            .factor_unwanted = time,
            .factor_of_interest = condition,
            method = "combat"
        )

    # --- Cellularity Deconvolution [] ---
    # Key functions: deconvolve_cellularity
    se_mini.cibersort <- se_mini.aggr |>
        deconvolve_cellularity(
            action = "get",
            cores = 1,
            prefix = "cibersort__"
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
        write.csv(as.data.frame(.main), "${prefix}_tidybulk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_tidybulk_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_tidybulk_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYBULK:", paste0("    tidybulk: ", as.character(packageVersion("tidybulk")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidybulk_results.csv
    touch ${prefix}_tidybulk_output.rds
    echo "BIOC_TIDYBULK:" > versions.yml
    echo "    tidybulk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYBULK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYBULK(ch_input)

    emit:
    results  = BIOC_TIDYBULK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYBULK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYBULK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYBULK.out.versions  // channel: path(versions.yml)
}
