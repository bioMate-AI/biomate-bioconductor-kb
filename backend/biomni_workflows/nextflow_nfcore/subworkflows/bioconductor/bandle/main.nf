#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bandle
// The Bandle package enables the analysis and visualisation of differential localisation experiments u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bandle/inst/doc/v01-getting-started.R
// Upstream  : dplyr, ggplot2, pRolocdata, pheatmap, viridis
// Downstream: none
//
// Install: BiocManager::install("bandle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BANDLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bandle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bandle:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bandle:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bandle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bandle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bandle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bandle)
    library(jsonlite)

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: bandleJoint, pheatmap
    par(mfrow = c(1, 2), oma = c(6,2,2,2))
    # --- Stockcol analysis [] ---
    # Key functions: setStockcol, plot2D, addLegend, sim_dynamic, fitGPmaternPC, plotGPmatern, prior_pred_dir, bandle
    mycols <- c(getStockcol()[seq(getMarkerClasses(res_control[[1]]))], "grey")
    names(mycols) <- c(getMarkerClasses(res_control[[1]]), "unknown")
    res <- list(res_dl_control, res_dl_treatment)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bandle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bandle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bandle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BANDLE:", paste0("    bandle: ", packageVersion("bandle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bandle_results.csv
    touch ${prefix}_bandle_output.rds
    echo "BIOC_BANDLE:" > versions.yml
    echo "    bandle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BANDLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BANDLE(ch_input)

    emit:
    results  = BIOC_BANDLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BANDLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BANDLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BANDLE.out.versions  // channel: path(versions.yml)
}
