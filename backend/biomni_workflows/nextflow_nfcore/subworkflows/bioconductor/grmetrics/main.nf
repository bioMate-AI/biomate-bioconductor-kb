#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GRmetrics
// Functions for calculating and visualizing growth-rate inhibition (GR) metrics.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GRmetrics/inst/doc/GRmetrics-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GRmetrics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRMETRICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-grmetrics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-grmetrics:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-grmetrics:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_grmetrics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_grmetrics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_grmetrics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRbox)
    library(GRdrawDRC)
    library(GRgetGroupVars)
    library(GRgetMetrics)
    library(GRgetValues)
    library(GRscatter)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(inputCaseA)
    # --- Head [] ---
    # Key functions: GRgetMetrics
    ---------------------------------------------------------------------
    head(GRgetMetrics(drc_output))
    # --- Head [] ---
    # Key functions: GRgetValues
    ---------------------------------------------------------------------
    head(GRgetValues(drc_output))
    # --- Grgetgroupvars [] ---
    # Key functions: GRgetGroupVars
    ---------------------------------------------------------------------
    GRgetGroupVars(drc_output)
    # --- Grdrawdrc [] ---
    # Key functions: GRdrawDRC
    ---------------------------------------------------------------------
    # Draw dose-response curves
    GRdrawDRC(drc_output)
    GRdrawDRC(drc_output, experiments = c('BT20 drugA', 'MCF10A drugA',
                                          'MCF7 drugA'))
    # --- Grscatter [] ---
    # Key functions: GRscatter, GRbox
    ---------------------------------------------------------------------
    # Draw scatterplots
    GRscatter(output1, 'GR50', 'agent', c('drugA','drugD'), 'drugB')
    GRscatter(output1, 'GR50', 'agent', c('drugA','drugD'), 'drugB',
              plotly = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_grmetrics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_grmetrics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_grmetrics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GRMETRICS:", paste0("    grmetrics: ", packageVersion("GRmetrics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grmetrics_results.csv
    touch ${prefix}_grmetrics_output.rds
    echo "BIOC_GRMETRICS:" > versions.yml
    echo "    grmetrics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GRMETRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GRMETRICS(ch_input)

    emit:
    results  = BIOC_GRMETRICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GRMETRICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GRMETRICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GRMETRICS.out.versions  // channel: path(versions.yml)
}
