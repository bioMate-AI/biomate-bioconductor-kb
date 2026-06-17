#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dir.expiry
// Implements an expiration system for access to versioned directories. Directories that have not been 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dir.expiry/inst/doc/userguide.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("dir.expiry")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIR_EXPIRY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dir_expiry"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dir_expiry_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dir_expiry_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dir_expiry_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("dir.expiry", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(dir.expiry)
    library(jsonlite)

    # --- Touchdirectory [] ---
    # Key functions: touchDirectory
    ---------------------------------------------------------------------
    library(dir.expiry)
    touchDirectory(version.dir)
    # --- Files [] ---
    # Key functions: files, path
    ---------------------------------------------------------------------
    list.files(cache.path)
    cat(readLines(file.path(cache.path, "1.0.0_dir.expiry")), sep="\n")
    # --- Unlockdirectory [] ---
    # Key functions: unlockDirectory
    ---------------------------------------------------------------------
    unlockDirectory(lock)

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
        write.csv(as.data.frame(.main), "${prefix}_dir_expiry_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_dir_expiry_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_dir_expiry_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIR_EXPIRY:", paste0("    dir_expiry: ", as.character(packageVersion("dir.expiry")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dir_expiry_results.csv
    touch ${prefix}_dir_expiry_output.rds
    echo "BIOC_DIR_EXPIRY:" > versions.yml
    echo "    dir_expiry: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIR_EXPIRY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIR_EXPIRY(ch_input)

    emit:
    results  = BIOC_DIR_EXPIRY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIR_EXPIRY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIR_EXPIRY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIR_EXPIRY.out.versions  // channel: path(versions.yml)
}
