#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rqc
// Rqc is an optimised tool designed for quality control and assessment of high-throughput sequencing d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rqc/inst/doc/Rqc.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Rqc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rqc:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rqc:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rqc)
    library(jsonlite)

    # --- Rqc analysis [] ---
    # Key functions: rqc, rqcQA, rqcReadQualityBoxPlot, rqcReadQualityPlot, rqcCycleAverageQualityPlot, rqcReadFrequencyPlot, rqcFileHeatmap, rqcReadWidthPlot
    df <- rqcCycleAverageQualityCalc(qa)
    cycle <- as.numeric(levels(df$cycle))[df$cycle]
    plot(cycle, df$quality, col = df$filename, xlab='Cycle', ylab='Quality Score')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RQC:", paste0("    rqc: ", packageVersion("Rqc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rqc_results.csv
    touch ${prefix}_rqc_output.rds
    echo "BIOC_RQC:" > versions.yml
    echo "    rqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RQC(ch_input)

    emit:
    results  = BIOC_RQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RQC.out.versions  // channel: path(versions.yml)
}
