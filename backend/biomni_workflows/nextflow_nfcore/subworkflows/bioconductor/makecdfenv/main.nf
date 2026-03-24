#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: makecdfenv
// This package has two functions. One reads a Affymetrix chip description file (CDF) and creates a has
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/makecdfenv/inst/doc/makecdfenv.R
// Upstream  : none
// Downstream: altcdfenvs
//
// Install: BiocManager::install("makecdfenv")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAKECDFENV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-makecdfenv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-makecdfenv:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-makecdfenv:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_makecdfenv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_makecdfenv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_makecdfenv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(makecdfenv)
    library(jsonlite)

    # --- Cleancdfname [] ---
    # Key functions: cleancdfname
    cat("HG_U95Av2 is",cleancdfname("HG_U95Av2"),"\n")
    cat("HG-133A is",cleancdfname("HG-133A"),"\n")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_makecdfenv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_makecdfenv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_makecdfenv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAKECDFENV:", paste0("    makecdfenv: ", packageVersion("makecdfenv"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_makecdfenv_results.csv
    touch ${prefix}_makecdfenv_output.rds
    echo "BIOC_MAKECDFENV:" > versions.yml
    echo "    makecdfenv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAKECDFENV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAKECDFENV(ch_input)

    emit:
    results  = BIOC_MAKECDFENV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAKECDFENV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAKECDFENV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAKECDFENV.out.versions  // channel: path(versions.yml)
}
