#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TileDBArray
// Implements a DelayedArray backend for reading and writing dense or sparse arrays in the TileDB forma
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TileDBArray/inst/doc/userguide.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("TileDBArray")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TILEDBARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tiledbarray"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tiledbarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tiledbarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tiledbarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("TileDBArray", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(TileDBArray)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rnorm, writeTileDBArray
    ---------------------------------------------------------------------
    X <- matrix(rnorm(1000), ncol=10)
    library(TileDBArray)
    writeTileDBArray(X)
    # --- Rsparsematrix [] ---
    # Key functions: rsparsematrix, writeTileDBArray
    ---------------------------------------------------------------------
    Y <- Matrix::rsparsematrix(1000, 1000, density=0.01)
    writeTileDBArray(Y)
    # --- Writetiledbarray [] ---
    # Key functions: writeTileDBArray
    ---------------------------------------------------------------------
    writeTileDBArray(Y > 0)
    # --- Rownames [] ---
    # Key functions: writeTileDBArray
    ---------------------------------------------------------------------
    rownames(X) <- sprintf("GENE_%i", seq_len(nrow(X)))
    colnames(X) <- sprintf("SAMP_%i", seq_len(ncol(X)))
    writeTileDBArray(X)
    # --- Colsums [] ---
    # Key functions: colSums, runif
    ---------------------------------------------------------------------
    colSums(out)
    out %*% runif(ncol(out))
    # --- Matrix [] ---
    # Key functions: rnorm, tempfile, writeTileDBArray
    ---------------------------------------------------------------------
    X <- matrix(rnorm(1000), ncol=10)
    path <- tempfile()
    writeTileDBArray(X, path=path, attr="WHEE")

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
        write.csv(as.data.frame(.main), "${prefix}_tiledbarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_tiledbarray_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_tiledbarray_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TILEDBARRAY:", paste0("    tiledbarray: ", as.character(packageVersion("TileDBArray")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tiledbarray_results.csv
    touch ${prefix}_tiledbarray_output.rds
    echo "BIOC_TILEDBARRAY:" > versions.yml
    echo "    tiledbarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TILEDBARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TILEDBARRAY(ch_input)

    emit:
    results  = BIOC_TILEDBARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TILEDBARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TILEDBARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TILEDBARRAY.out.versions  // channel: path(versions.yml)
}
