#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bioCancer
// This package is a Shiny App to visualize and analyse interactively Multi-Assays of Cancer Genomic Da
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/bioCancer/inst/doc/bioCancer.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("bioCancer")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BIOCANCER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocancer"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocancer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocancer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocancer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("bioCancer", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(bioCancer)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: mutate_each, funs
    ## transform variable
    r_data[["epiGenomics"]] <- mutate_each(r_data[["epiGenomics"]], funs(log), ext = "_log", mRNA, Met450)

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
        write.csv(as.data.frame(.main), "${prefix}_biocancer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_biocancer_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_biocancer_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCANCER:", paste0("    biocancer: ", as.character(packageVersion("bioCancer")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocancer_results.csv
    touch ${prefix}_biocancer_output.rds
    echo "BIOC_BIOCANCER:" > versions.yml
    echo "    biocancer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCANCER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCANCER(ch_input)

    emit:
    results  = BIOC_BIOCANCER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCANCER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCANCER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCANCER.out.versions  // channel: path(versions.yml)
}
