#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidySpatialExperiment
// tidySpatialExperiment provides a bridge between the SpatialExperiment package and the tidyverse ecos
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidySpatialExperiment/inst/doc/overview.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tidySpatialExperiment")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TIDYSPATIALEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidyspatialexperiment"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidyspatialexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidyspatialexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidyspatialexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidySpatialExperiment)
    library(jsonlite)

    # --- Spatial Spot Filtering [] ---
    # Key functions: filter, mutate
    spe_filtered <- spe |>
        filter(sample_id == "section1" & in_tissue) |>
        mutate(
            high_count = array_col < 5,
            in_region = array_row < 10
        )

    # --- Feature Expression Joining [] ---
    # Key functions: join_features
    spe_joined <- spe |>
        join_features(
            features = c("ENSMUSG00000025915", "ENSMUSG00000042501"),
            shape = "wide"
        )

    # --- Spatial Gating [] ---
    # Key functions: gate, filter
    spe_gated <- spe |>
        gate(programmatic_gates = demo_brush_data) |>
        filter(!is.na(.gated))

    # --- Pseudobulk Aggregation [] ---
    # Key functions: aggregate_cells
    spe_aggregated <- spe |>
        aggregate_cells(
            in_tissue,
            assays = "counts"
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
        write.csv(as.data.frame(.main), "${prefix}_tidyspatialexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_tidyspatialexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_tidyspatialexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYSPATIALEXPERIMENT:", paste0("    tidyspatialexperiment: ", as.character(packageVersion("tidySpatialExperiment")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidyspatialexperiment_results.csv
    touch ${prefix}_tidyspatialexperiment_output.rds
    echo "BIOC_TIDYSPATIALEXPERIMENT:" > versions.yml
    echo "    tidyspatialexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYSPATIALEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYSPATIALEXPERIMENT(ch_input)

    emit:
    results  = BIOC_TIDYSPATIALEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYSPATIALEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYSPATIALEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYSPATIALEXPERIMENT.out.versions  // channel: path(versions.yml)
}
