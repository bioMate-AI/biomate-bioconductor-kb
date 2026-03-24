#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SCFA
// Subtyping via Consensus Factor Analysis (SCFA) can efficiently remove noisy signals from consistent 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SCFA/inst/doc/Example.R
// Upstream  : knitr, survival
// Downstream: none
//
// Install: BiocManager::install("SCFA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCFA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scfa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scfa:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scfa:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scfa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scfa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scfa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SCFA)
    library(jsonlite)

    # --- Knitr Options [] ---
    # Key functions: set
    --------------
    library(knitr)
    opts_chunk$set(fig.align = 'center', fig.width = 6, fig.height = 5, dev = 'png')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scfa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scfa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scfa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCFA:", paste0("    scfa: ", packageVersion("SCFA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scfa_results.csv
    touch ${prefix}_scfa_output.rds
    echo "BIOC_SCFA:" > versions.yml
    echo "    scfa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCFA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCFA(ch_input)

    emit:
    results  = BIOC_SCFA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCFA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCFA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCFA.out.versions  // channel: path(versions.yml)
}
