#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: splots
// This package is here to support legacy usages of it, but it should not be used for new code developm
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/splots/inst/doc/splots.R
// Upstream  : dplyr, ggplot2
// Downstream: HD2013SGI
//
// Install: BiocManager::install("splots")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLOTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-splots"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-splots:1.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-splots:1.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_splots_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_splots_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_splots_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(splots)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, facet_wrap, scale_fill_gradient
    library("ggplot2")
    ggplot(sgi, aes(x = col, y = row, fill = count)) + geom_raster() +
    facet_wrap(vars(plate), ncol = 4) +
    # --- assert_that [] ---
    # Key functions: assert_that, all
    plateNames = unique(featuresPerWell[[1]]$plate)
    assertthat::assert_that(length(plateNames) >= np)
    plateNames = plateNames[seq_len(np)]
    # --- plot Screen [] ---
    # Key functions: plotScreen
    splots::plotScreen(xl, nx = nx, ny = ny, ncol = 4,
    fill = c("white", "#00008B"),
    zrange = c(0, max(unlist(xl), na.rm = TRUE)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_splots_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_splots_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_splots_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPLOTS:", paste0("    splots: ", packageVersion("splots"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splots_results.csv
    touch ${prefix}_splots_output.rds
    echo "BIOC_SPLOTS:" > versions.yml
    echo "    splots: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPLOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPLOTS(ch_input)

    emit:
    results  = BIOC_SPLOTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPLOTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPLOTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPLOTS.out.versions  // channel: path(versions.yml)
}
