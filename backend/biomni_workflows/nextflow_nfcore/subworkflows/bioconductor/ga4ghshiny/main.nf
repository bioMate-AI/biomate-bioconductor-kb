#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GA4GHshiny
// GA4GHshiny package provides an easy way to interact with data servers based on Global Alliance for G
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/GA4GHshiny/inst/doc/GA4GHshiny.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GA4GHshiny")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_GA4GHSHINY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ga4ghshiny"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ga4ghshiny_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ga4ghshiny_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ga4ghshiny_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GA4GHshiny", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(GA4GHshiny)
    library(jsonlite)

    # --- Interactive Genomic Data Exploration [] ---
    # Key functions: app
    # Initialize the GA4GH Shiny application pointing to the 1000 Genomes Project
    # This allows interactive exploration of genomic variants and metadata.
    genomic_app <- GA4GHshiny::app(
        host = "http://1kgenomes.ga4gh.org/",
        serverName = "Hosting Thousand Genomes Project"
    )

    # --- Local GA4GH Server Visualization [] ---
    # Key functions: app
    # Launch the GA4GH Shiny application connected to a local server instance.
    # This is useful for visualizing private or in-house GA4GH-compliant data.
    local_visualization <- GA4GHshiny::app(
        host = "http://localhost:8000/",
        serverName = "Local GA4GH Server"
    )

    # --- Public Repository Querying [] ---
    # Key functions: app
    # Configure the GA4GH Shiny application to connect to a public API endpoint.
    # This enables querying global genomic repositories interactively.
    public_query_app <- GA4GHshiny::app(
        host = "https://gl-api.ga4gh.org/",
        serverName = "Global Alliance API"
    )


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
        write.csv(as.data.frame(.main), "${prefix}_ga4ghshiny_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_ga4ghshiny_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_ga4ghshiny_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_GA4GHSHINY:", paste0("    ga4ghshiny: ", as.character(packageVersion("GA4GHshiny")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ga4ghshiny_results.csv
    touch ${prefix}_ga4ghshiny_output.rds
    echo "BIOC_GA4GHSHINY:" > versions.yml
    echo "    ga4ghshiny: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GA4GHSHINY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GA4GHSHINY(ch_input)

    emit:
    results  = BIOC_GA4GHSHINY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GA4GHSHINY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GA4GHSHINY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GA4GHSHINY.out.versions  // channel: path(versions.yml)
}
