#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: weaver
// This package provides enhancements on the Sweave() function in the base package.  In particular a fa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/weaver/inst/doc/weaver_howTo.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("weaver")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_WEAVER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-weaver"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_weaver_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_weaver_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_weaver_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("weaver", "Sweave", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(weaver)
    library(Sweave)
    library(jsonlite)

    # --- Report Template Setup [] ---
    # Key functions: weaver
    doc_template <- system.file("extdata/doc1.Rnw", package = "weaver")
    weaver_driver <- weaver()
    driver_name <- weaver_driver\$name
    is_valid_driver <- !is.null(weaver_driver\$runcode)

    # --- Cached Document Compilation [] ---
    # Key functions: weaver
    doc_path <- system.file("extdata/doc1.Rnw", package = "weaver")
    temp_dir <- tempdir()
    old_dir <- setwd(temp_dir)
    utils::Sweave(
        file = doc_path,
        driver = weaver()
    )
    setwd(old_dir)

    # --- Parallel Report Generation [] ---
    # Key functions: weaver
    doc_path_2 <- system.file("extdata/doc2.Rnw", package = "weaver")
    temp_dir_2 <- tempdir()
    old_dir_2 <- setwd(temp_dir_2)
    utils::Sweave(
        file = doc_path_2,
        driver = weaver()
    )
    setwd(old_dir_2)


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
        write.csv(as.data.frame(.main), "${prefix}_weaver_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_weaver_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_weaver_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_WEAVER:", paste0("    weaver: ", as.character(packageVersion("weaver")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weaver_results.csv
    touch ${prefix}_weaver_output.rds
    echo "BIOC_WEAVER:" > versions.yml
    echo "    weaver: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WEAVER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_WEAVER(ch_input)

    emit:
    results  = BIOC_WEAVER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WEAVER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WEAVER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WEAVER.out.versions  // channel: path(versions.yml)
}
