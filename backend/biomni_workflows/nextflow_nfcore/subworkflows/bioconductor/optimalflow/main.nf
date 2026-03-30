#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: optimalFlow
// Optimal-transport techniques applied to supervised flow cytometry gating.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/optimalFlow/inst/doc/optimalFlow_vignette.R
// Upstream  : optimalFlowData, ellipse
// Downstream: none
//
// Install: BiocManager::install("optimalFlow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPTIMALFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-optimalflow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-optimalflow:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-optimalflow:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_optimalflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_optimalflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_optimalflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(optimalFlow)
    library(jsonlite)

    # --- Database analysis [] ---
    # Key functions: buildDatabase, optimalFlowTemplates, cytoPlotDatabase, cytoPlotDatabase3d, cytoPlot, cytoPlot3d, optimalFlowClassification, f1ScoreVoting
    cytoPlotDatabase3d(templates.optimalFlow$database.elliptical[which(templates.optimalFlow$clustering == 3)], dimensions = c(4, 3, 9), xlim = c(0, 8000), ylim = c(0, 8000), zlim = c(0, 8000), colour = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_optimalflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_optimalflow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_optimalflow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPTIMALFLOW:", paste0("    optimalflow: ", packageVersion("optimalFlow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_optimalflow_results.csv
    touch ${prefix}_optimalflow_output.rds
    echo "BIOC_OPTIMALFLOW:" > versions.yml
    echo "    optimalflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPTIMALFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OPTIMALFLOW(ch_input)

    emit:
    results  = BIOC_OPTIMALFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPTIMALFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPTIMALFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPTIMALFLOW.out.versions  // channel: path(versions.yml)
}
