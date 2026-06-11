#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DelayedDataFrame
// Based on the standard DataFrame metaphor, we are trying to implement the feature of delayed operatio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DelayedDataFrame/inst/doc/DelayedDataFrame.R
// Upstream  : GDSArray
// Downstream: none
//
// Install: BiocManager::install("DelayedDataFrame")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_DELAYEDDATAFRAME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-delayeddataframe"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_delayeddataframe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_delayeddataframe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_delayeddataframe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DelayedDataFrame", "GDSArray", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(DelayedDataFrame)
    library(GDSArray)
    library(jsonlite)

    # --- seq Example File Name [] ---
    # Key functions: seqExampleFileName, gdsnodes, GDSArray
    library(GDSArray)
    file <- SeqArray::seqExampleFileName("gds")
    gdsnodes(file)
    # --- Delayed Data Frame [] ---
    # Key functions: DelayedDataFrame
    ddf <- DelayedDataFrame(varid, DP)  ## only accommodate 1D GDSArrays with same length
    # --- lazy Index [] ---
    # Key functions: lazyIndex
    lazyIndex(ddf)
    nrow(ddf)
    rownames(ddf)

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
        write.csv(as.data.frame(.main), "${prefix}_delayeddataframe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_delayeddataframe_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_delayeddataframe_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_DELAYEDDATAFRAME:", paste0("    delayeddataframe: ", as.character(packageVersion("DelayedDataFrame")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delayeddataframe_results.csv
    touch ${prefix}_delayeddataframe_output.rds
    echo "BIOC_DELAYEDDATAFRAME:" > versions.yml
    echo "    delayeddataframe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DELAYEDDATAFRAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DELAYEDDATAFRAME(ch_input)

    emit:
    results  = BIOC_DELAYEDDATAFRAME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DELAYEDDATAFRAME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DELAYEDDATAFRAME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DELAYEDDATAFRAME.out.versions  // channel: path(versions.yml)
}
