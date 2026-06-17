#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEpathways
// This package contains diverse functionality to extend the usage of the iSEE package, including addit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEpathways/inst/doc/gene-ontology.R
// Upstream  : RefManageR, SummarizedExperiment, airway, edgeR, fgsea
// Downstream: none
//
// Install: BiocManager::install("iSEEpathways")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ISEEPATHWAYS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseepathways"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(numeric)

    output:
    tuple val(meta), path("${meta.id}_iseepathways_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseepathways_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseepathways_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("PrintBibliography", "jsonlite", "org.Hs.eg.db", "fgsea", "rmarkdown", "knitr", "sessioninfo")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(PrintBibliography)
    library(jsonlite)

    # --- "start" [] ---
    # Key functions: split, lengths, rnorm, fgsea
    library("org.Hs.eg.db")
    library("fgsea")
    pathways <- select(org.Hs.eg.db, keys(org.Hs.eg.db, "SYMBOL"), c("GOALL"), keytype = "SYMBOL")
    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("gene-ontology.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- diff [] ---
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
        write.csv(as.data.frame(.main), "${prefix}_iseepathways_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_iseepathways_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_iseepathways_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEPATHWAYS:", paste0("    iseepathways: ", as.character(packageVersion("iSEEpathways")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseepathways_results.csv
    touch ${prefix}_iseepathways_output.rds
    echo "BIOC_ISEEPATHWAYS:" > versions.yml
    echo "    iseepathways: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEPATHWAYS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(numeric) ]

    main:
    BIOC_ISEEPATHWAYS(ch_input)

    emit:
    results  = BIOC_ISEEPATHWAYS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEPATHWAYS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEPATHWAYS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEPATHWAYS.out.versions  // channel: path(versions.yml)
}
