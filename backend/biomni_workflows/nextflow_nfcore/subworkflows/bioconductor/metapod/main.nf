#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metapod
// Implements a variety of methods for combining p-values in differential analyses of genome-scale data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metapod/inst/doc/overview.R
// Upstream  : BiocStyle, knitr
// Downstream: none
//
// Install: BiocManager::install("metapod")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAPOD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metapod"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metapod:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metapod:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metapod_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metapod_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metapod_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metapod)
    library(jsonlite)

    # --- Rbeta [] ---
    # Key functions: rbeta, parallelSimes
    ---------------------------------------------------------------------
    library(metapod)
    p1 <- rbeta(10000, 0.5, 1)
    p2 <- rbeta(10000, 0.5, 1)
    par.combined <- parallelSimes(list(p1, p2))
    # --- Rbeta [] ---
    # Key functions: rbeta, sample, groupedSimes
    ---------------------------------------------------------------------
    p <- rbeta(10000, 0.5, 1)
    g <- sample(100, length(p), replace=TRUE)
    gr.combined <- groupedSimes(p, g)
    str(gr.combined)
    # --- Rnorm [] ---
    # Key functions: rnorm, summarizeParallelDirection
    ---------------------------------------------------------------------
    logfc1 <- rnorm(10000)
    logfc2 <- rnorm(10000)
    par.dir <- summarizeParallelDirection(list(logfc1, logfc2),
        influential = par.combined$influential)
    # --- Countparalleldirection [] ---
    # Key functions: countParallelDirection
    ---------------------------------------------------------------------
    par.dir2 <- countParallelDirection(list(p1, p2), list(logfc1, logfc2))
    str(par.dir2)
    # --- Combinegroupedpvalues [] ---
    # Key functions: combineGroupedPValues
    ---------------------------------------------------------------------
    gr.combined2 <- combineGroupedPValues(p, g, method="holm-min")
    str(gr.combined2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metapod_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metapod_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metapod_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METAPOD:", paste0("    metapod: ", packageVersion("metapod"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metapod_results.csv
    touch ${prefix}_metapod_output.rds
    echo "BIOC_METAPOD:" > versions.yml
    echo "    metapod: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METAPOD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METAPOD(ch_input)

    emit:
    results  = BIOC_METAPOD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METAPOD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METAPOD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METAPOD.out.versions  // channel: path(versions.yml)
}
