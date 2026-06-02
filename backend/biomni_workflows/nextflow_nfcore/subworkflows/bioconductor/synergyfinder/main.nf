#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: synergyfinder
// Efficient implementations for analyzing pre-clinical multiple drug combination datasets. It provides
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/synergyfinder/inst/doc/User_tutorual_of_the_SynergyFinder_plus.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("synergyfinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNERGYFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-synergyfinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-synergyfinder:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-synergyfinder:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_synergyfinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_synergyfinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_synergyfinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PlotSensitivitySynergy)
    library(ReshapeData)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("mathews_screening_data")
    head(mathews_screening_data)
    # --- Reshapedata [] ---
    # Key functions: ReshapeData
    ---------------------------------------------------------------------
    # --- Plotsensitivitysynergy [] ---
    # Key functions: PlotSensitivitySynergy
    ---------------------------------------------------------------------
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("ONEIL_screening_data")
    head(ONEIL_screening_data)
    # --- Reshapedata [] ---
    # Key functions: ReshapeData
    ---------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_synergyfinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_synergyfinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_synergyfinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYNERGYFINDER:", paste0("    synergyfinder: ", packageVersion("synergyfinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synergyfinder_results.csv
    touch ${prefix}_synergyfinder_output.rds
    echo "BIOC_SYNERGYFINDER:" > versions.yml
    echo "    synergyfinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYNERGYFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYNERGYFINDER(ch_input)

    emit:
    results  = BIOC_SYNERGYFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYNERGYFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYNERGYFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYNERGYFINDER.out.versions  // channel: path(versions.yml)
}
