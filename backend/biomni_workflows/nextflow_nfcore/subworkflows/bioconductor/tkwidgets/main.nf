#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tkWidgets
// Widgets to provide user interfaces. tcltk should have been installed for the widgets to run.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tkWidgets/inst/doc/importWizard.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tkWidgets")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TKWIDGETS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tkwidgets"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tkwidgets_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tkwidgets_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tkwidgets_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("tkWidgets", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(tkWidgets)
    library(jsonlite)

    # --- Tolatex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

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
        write.csv(as.data.frame(.main), "${prefix}_tkwidgets_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_tkwidgets_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_tkwidgets_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TKWIDGETS:", paste0("    tkwidgets: ", as.character(packageVersion("tkWidgets")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tkwidgets_results.csv
    touch ${prefix}_tkwidgets_output.rds
    echo "BIOC_TKWIDGETS:" > versions.yml
    echo "    tkwidgets: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TKWIDGETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TKWIDGETS(ch_input)

    emit:
    results  = BIOC_TKWIDGETS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TKWIDGETS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TKWIDGETS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TKWIDGETS.out.versions  // channel: path(versions.yml)
}
