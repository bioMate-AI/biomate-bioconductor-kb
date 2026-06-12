#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RbcBook1
// tools for building book
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RbcBook1/inst/doc/RbcBook1.R
// Upstream  : graph
// Downstream: none
//
// Install: BiocManager::install("RbcBook1")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_RBCBOOK1 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbcbook1"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbcbook1_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbcbook1_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbcbook1_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("RbcBook1", "jsonlite", "graph")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(RbcBook1)
    library(jsonlite)

    # --- Cache [] ---
    # Key functions: cache, randomGraph
    library(graph)
    library(RbcBook1)
    cache(bigran <- randomGraph( paste("a", 1:50), 1:30 , .4 ))

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
        write.csv(as.data.frame(.main), "${prefix}_rbcbook1_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rbcbook1_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rbcbook1_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBCBOOK1:", paste0("    rbcbook1: ", as.character(packageVersion("RbcBook1")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbcbook1_results.csv
    touch ${prefix}_rbcbook1_output.rds
    echo "BIOC_RBCBOOK1:" > versions.yml
    echo "    rbcbook1: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBCBOOK1_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBCBOOK1(ch_input)

    emit:
    results  = BIOC_RBCBOOK1.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBCBOOK1.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBCBOOK1.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBCBOOK1.out.versions  // channel: path(versions.yml)
}
