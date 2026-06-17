#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsCoreUtils
// MsCoreUtils defines low-level functions for mass spectrometry data and is independent of any high-le
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsCoreUtils/inst/doc/MsCoreUtils.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MsCoreUtils")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MSCOREUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mscoreutils"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mscoreutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mscoreutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mscoreutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MsCoreUtils", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(MsCoreUtils)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rnorm, robustSummary
    ---------------------------------------------------------------------
    x <- matrix(rnorm(30), nrow = 3)
    colnames(x) <- letters[1:10]
    rownames(x) <- LETTERS[1:3]
    x

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
        write.csv(as.data.frame(.main), "${prefix}_mscoreutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_mscoreutils_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_mscoreutils_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSCOREUTILS:", paste0("    mscoreutils: ", as.character(packageVersion("MsCoreUtils")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mscoreutils_results.csv
    touch ${prefix}_mscoreutils_output.rds
    echo "BIOC_MSCOREUTILS:" > versions.yml
    echo "    mscoreutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSCOREUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSCOREUTILS(ch_input)

    emit:
    results  = BIOC_MSCOREUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSCOREUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSCOREUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSCOREUTILS.out.versions  // channel: path(versions.yml)
}
