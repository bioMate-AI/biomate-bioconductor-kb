#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEde
// This package contains diverse functionality to extend the usage of the iSEE package, including addit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEde/inst/doc/annotations.R
// Upstream  : DESeq2, RefManageR, airway, edgeR, iSEE
// Downstream: none
//
// Install: BiocManager::install("iSEEde")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ISEEDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseede"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iseede_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseede_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseede_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("PrintBibliography", "jsonlite", "rmarkdown", "knitr", "sessioninfo")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(PrintBibliography)
    library(jsonlite)

    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("annotations.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- Differential Expression [] ---
    # Key functions: diff
    totalTime <- diff(c(startTime, Sys.time()))
    round(totalTime, digits = 3)
    # --- session_info [] ---
    # Key functions: session_info
    library("sessioninfo")
    options(width = 120)
    session_info()
    # --- Print Bibliography [] ---
    # Key functions: PrintBibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

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
        write.csv(as.data.frame(.main), "${prefix}_iseede_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_iseede_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_iseede_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEDE:", paste0("    iseede: ", as.character(packageVersion("iSEEde")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseede_results.csv
    touch ${prefix}_iseede_output.rds
    echo "BIOC_ISEEDE:" > versions.yml
    echo "    iseede: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEEDE(ch_input)

    emit:
    results  = BIOC_ISEEDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEDE.out.versions  // channel: path(versions.yml)
}
