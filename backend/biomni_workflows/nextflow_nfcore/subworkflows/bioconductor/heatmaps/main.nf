#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: heatmaps
// This package provides functions for plotting heatmaps of genome-wide data across genomic intervals, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/heatmaps/inst/doc/heatmaps.R
// Upstream  : rtracklayer, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("heatmaps")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HEATMAPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-heatmaps"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-heatmaps:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-heatmaps:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_heatmaps_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_heatmaps_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_heatmaps_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(heatmaps)
    library(jsonlite)

    # --- Data scaling normalization [] ---
    # Key functions: plotHeatmapList, plotHeatmapMeta, scale, smoothHeatmap, plot_legend, plotHeatmap
    tata_pwm_scan_30p = PWMScanHeatmap(seq_30p, tata_pwm, coords=coords, label="TATA")
    tata_pwm_scan_30p_smoothed = smoothHeatmap(tata_pwm_scan_30p, algorithm="blur", output.size=c(250, 500))
    scale(tata_pwm_scan_30p_smoothed) = c(40, 60)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_heatmaps_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_heatmaps_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_heatmaps_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HEATMAPS:", paste0("    heatmaps: ", packageVersion("heatmaps"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_heatmaps_results.csv
    touch ${prefix}_heatmaps_output.rds
    echo "BIOC_HEATMAPS:" > versions.yml
    echo "    heatmaps: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HEATMAPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HEATMAPS(ch_input)

    emit:
    results  = BIOC_HEATMAPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HEATMAPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HEATMAPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HEATMAPS.out.versions  // channel: path(versions.yml)
}
