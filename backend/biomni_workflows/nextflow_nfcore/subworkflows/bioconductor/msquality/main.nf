#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsQuality
// The MsQuality provides functionality to calculate quality metrics for mass spectrometry-derived, spe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsQuality/inst/doc/MsQuality.R
// Upstream  : MsExperiment, Spectra, knitr
// Downstream: none
//
// Install: BiocManager::install("MsQuality")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSQUALITY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msquality"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msquality:1.6.2--r44_0' :
        'quay.io/biocontainers/bioconductor-msquality:1.6.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msquality_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msquality_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msquality_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MsQuality)
    library(DataFrame)
    library(MsExperiment)
    library(Spectra)
    library(jsonlite)

    # --- Load and Prepare Spectra Data [Quality Control] ---
    # Key functions: qualityMetrics
    data("Lee2019", package = "MsQuality")
    sps_comb <- c(sps_rplc, sps_hilic)
    avail_metrics <- qualityMetrics(sps_comb)
    sps_comb_subset <- sps_comb[
        grep("Sample.1_", sps_comb$dataOrigin), 
    ]

    # --- Calculate Spectra Quality Metrics [Quality Control] ---
    # Key functions: calculateMetrics, qualityMetrics
    metrics_sps_Q1 <- calculateMetrics(
        object = sps_comb_subset,
        metrics = qualityMetrics(sps_comb_subset),
        filterEmptySpectra = FALSE,
        relativeTo = "Q1",
        msLevel = 1L
    )
    metrics_sps_previous <- calculateMetrics(
        object = sps_comb_subset,
        metrics = qualityMetrics(sps_comb_subset),
        filterEmptySpectra = FALSE,
        relativeTo = "previous",
        msLevel = 1L
    )

    # --- Calculate MsExperiment Quality Metrics [Quality Control] ---
    # Key functions: calculateMetrics, qualityMetrics
    msexp_rplc_subset <- msexp_rplc[1:20]
    msexp_hilic_subset <- msexp_hilic[1:20]
    metrics_rplc_msexp <- calculateMetrics(
        object = msexp_rplc_subset,
        metrics = qualityMetrics(msexp_rplc_subset),
        filterEmptySpectra = TRUE,
        relativeTo = "Q1",
        msLevel = 1L
    )
    metrics_hilic_msexp <- calculateMetrics(
        object = msexp_hilic_subset,
        metrics = qualityMetrics(msexp_hilic_subset),
        filterEmptySpectra = TRUE,
        relativeTo = "Q1",
        msLevel = 1L
    )

    # --- Quality Control Visualization [Visualisation] ---
    # Key functions: plotMetric
    metrics_msexp <- rbind(metrics_rplc_msexp, metrics_hilic_msexp)
    plotMetric(
        qc = metrics_msexp, 
        metric = "numberSpectra"
    )
    plotMetric(
        qc = metrics_msexp, 
        metric = "ticQuartileToQuartileLogRatio"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msquality_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msquality_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msquality_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSQUALITY:", paste0("    msquality: ", packageVersion("MsQuality"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msquality_results.csv
    touch ${prefix}_msquality_output.rds
    echo "BIOC_MSQUALITY:" > versions.yml
    echo "    msquality: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSQUALITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSQUALITY(ch_input)

    emit:
    results  = BIOC_MSQUALITY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSQUALITY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSQUALITY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSQUALITY.out.versions  // channel: path(versions.yml)
}
