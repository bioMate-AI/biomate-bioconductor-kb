#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chihaya
// Saves the delayed operations of a DelayedArray to a HDF5 file. This enables efficient recovery of th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chihaya/inst/doc/userguide.R
// Upstream  : BiocStyle, DelayedArray, HDF5Array, Matrix
// Downstream: none
//
// Install: BiocManager::install("chihaya")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_CHIHAYA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chihaya"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chihaya_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chihaya_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chihaya_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DelayedArray", "HDF5Array", "jsonlite", "Matrix")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(DelayedArray)
    library(HDF5Array)
    library(jsonlite)

    # --- Delayedarray [] ---
    # Key functions: DelayedArray, runif, showtree
    ---------------------------------------------------------------------
    library(DelayedArray)
    x <- DelayedArray(matrix(runif(1000), ncol=10))
    x <- x[11:15,] / runif(5)
    x <- log2(x + 1)
    # --- Loaddelayed [] ---
    # Key functions: loadDelayed
    ---------------------------------------------------------------------
    y <- loadDelayed(tmp)
    y
    # --- Rsparsematrix [] ---
    # Key functions: rsparsematrix, DelayedArray, runif, tempfile, saveDelayed, h5ls, info
    ---------------------------------------------------------------------
    library(Matrix)
    x <- rsparsematrix(1000, 1000, density=0.01)
    x <- DelayedArray(x) + runif(1000)
    tmp <- tempfile(fileext=".h5")
    # --- Access INFO field from VCF [] ---
    # Key functions: HDF5Array, tempfile, saveDelayed, h5ls, info, loadDelayed
    ---------------------------------------------------------------------
    library(HDF5Array)
    test <- HDF5Array(tmp2, "data")
    stuff <- log2(test + 1)
    stuff

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
        write.csv(as.data.frame(.main), "${prefix}_chihaya_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_chihaya_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_chihaya_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIHAYA:", paste0("    chihaya: ", as.character(packageVersion("chihaya")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chihaya_results.csv
    touch ${prefix}_chihaya_output.rds
    echo "BIOC_CHIHAYA:" > versions.yml
    echo "    chihaya: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIHAYA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIHAYA(ch_input)

    emit:
    results  = BIOC_CHIHAYA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIHAYA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIHAYA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIHAYA.out.versions  // channel: path(versions.yml)
}
