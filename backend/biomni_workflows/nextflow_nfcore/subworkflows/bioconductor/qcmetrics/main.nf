#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qcmetrics
// The package provides a framework for generic quality control of data. It permits to create, manage a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qcmetrics/inst/doc/qcmetrics.R
// Upstream  : MSnbase, RforProteomics, ggplot2, mzR
// Downstream: none
//
// Install: BiocManager::install("qcmetrics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QCMETRICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qcmetrics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qcmetrics:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qcmetrics:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qcmetrics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qcmetrics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qcmetrics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(QcMetric)
    library(QcMetrics)
    library(jsonlite)

    # --- Combine peptide features to proteins [] ---
    # Key functions: fData, combineFeatures
    fData(psm)$modseq <- ## pep seq + PTM
    paste(fData(psm)$Peptide_Sequence,
    fData(psm)$Variable_Modifications, sep = "+")
    # --- Custom ggplot2 visualization [] ---
    # Key functions: qcdata, ggplot, geom_jitter, geom_boxplot
    plot(qcinc) <- function(object) {
    inc <- qcdata(object, "inc")
    tr <- qcdata(object, "tr")
    # --- Object metadata inspection [] ---
    # Key functions: QcMetric, qcdata, show, status, QcMetrics, metadata, mdata, rtime
    qcReport(n15qcm, reportname = "n15qcreport",
    title = expinfo(experimentData(psm))["title"],
    author = expinfo(experimentData(psm))["contact"],

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qcmetrics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qcmetrics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qcmetrics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QCMETRICS:", paste0("    qcmetrics: ", packageVersion("qcmetrics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qcmetrics_results.csv
    touch ${prefix}_qcmetrics_output.rds
    echo "BIOC_QCMETRICS:" > versions.yml
    echo "    qcmetrics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QCMETRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QCMETRICS(ch_input)

    emit:
    results  = BIOC_QCMETRICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QCMETRICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QCMETRICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QCMETRICS.out.versions  // channel: path(versions.yml)
}
