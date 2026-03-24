#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qsmooth
// Smooth quantile normalization is a generalization of quantile normalization, which is average of the
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qsmooth/inst/doc/qsmooth.R
// Upstream  : SummarizedExperiment, bodymapRat, quantro
// Downstream: none
//
// Install: BiocManager::install("qsmooth")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSMOOTH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qsmooth"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qsmooth:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qsmooth:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qsmooth_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qsmooth_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qsmooth_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qsmooth)
    library(jsonlite)

    # --- bodymap Rat [] ---
    # Key functions: bodymapRat
    library(SummarizedExperiment)
    library(bodymapRat)
    bm_dat <- bodymapRat()
    # --- col Data [] ---
    # Key functions: colData, assay, matboxplot
    library(quantro)
    par(mfrow=c(2,2))
    pd1 <- colData(bm_dat_e1)
    # --- qsmooth Plot Weights [] ---
    # Key functions: qsmoothPlotWeights, colData, assay, matboxplot
    qsmoothPlotWeights(qs_norm_e1)
    par(mfrow=c(2,2))
    pd1 <- colData(bm_dat_e1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qsmooth_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qsmooth_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qsmooth_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QSMOOTH:", paste0("    qsmooth: ", packageVersion("qsmooth"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qsmooth_results.csv
    touch ${prefix}_qsmooth_output.rds
    echo "BIOC_QSMOOTH:" > versions.yml
    echo "    qsmooth: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QSMOOTH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QSMOOTH(ch_input)

    emit:
    results  = BIOC_QSMOOTH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QSMOOTH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QSMOOTH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QSMOOTH.out.versions  // channel: path(versions.yml)
}
