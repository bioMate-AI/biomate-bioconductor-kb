#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rcollectl
// Provide functions to obtain instrumentation data on processes in a unix environment.  Parse output o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rcollectl/inst/doc/Rcollectl.R
// Upstream  : knitcitations, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("Rcollectl")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_RCOLLECTL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcollectl"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcollectl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcollectl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcollectl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rcollectl)
    library(jsonlite)

    # --- Cleanbib analysis [] ---
    # Key functions: cleanbib, cite_options, attr, cl_stop, plot_usage, cl_start, cl_timestamp, cl_result_path
    library("rmarkdown")
    system.time(render("Rcollectl.Rmd", "BiocStyle::html_document"))
    library("knitr")

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
        write.csv(as.data.frame(.main), "${prefix}_rcollectl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rcollectl_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rcollectl_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCOLLECTL:", paste0("    rcollectl: ", as.character(packageVersion("Rcollectl")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcollectl_results.csv
    touch ${prefix}_rcollectl_output.rds
    echo "BIOC_RCOLLECTL:" > versions.yml
    echo "    rcollectl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCOLLECTL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCOLLECTL(ch_input)

    emit:
    results  = BIOC_RCOLLECTL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCOLLECTL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCOLLECTL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCOLLECTL.out.versions  // channel: path(versions.yml)
}
