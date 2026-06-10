#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rebook
// Provides utilities to re-use content across chapters of a Bioconductor book. This is mostly based on
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rebook/inst/doc/userguide.R
// Upstream  : none
// Downstream: csawBook, OSCA, OSCA.advanced, OSCA.basic, OSCA.intro
//
// Install: BiocManager::install("rebook")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_REBOOK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rebook"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rebook_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rebook_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rebook_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rebook)
    library(jsonlite)

    # --- Link [] ---
    # Key functions: link
    ---------------------------------------------------------------------
    link("installation", "OSCA.intro")
    link("some-comments-on-experimental-design", "OSCA.intro")
    link("fig:sce-structure", "OSCA.intro")

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
        write.csv(as.data.frame(.main), "${prefix}_rebook_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rebook_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rebook_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_REBOOK:", paste0("    rebook: ", as.character(packageVersion("rebook")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rebook_results.csv
    touch ${prefix}_rebook_output.rds
    echo "BIOC_REBOOK:" > versions.yml
    echo "    rebook: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REBOOK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REBOOK(ch_input)

    emit:
    results  = BIOC_REBOOK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REBOOK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REBOOK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REBOOK.out.versions  // channel: path(versions.yml)
}
