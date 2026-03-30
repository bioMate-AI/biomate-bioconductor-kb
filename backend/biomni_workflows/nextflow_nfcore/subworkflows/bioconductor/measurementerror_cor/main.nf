#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MeasurementError.cor
// Two-stage measurement error model for correlation estimation with smaller bias than the usual sample
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MeasurementError.cor/inst/doc/MeasurementError.cor.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MeasurementError.cor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEASUREMENTERROR_COR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-measurementerror_cor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-measurementerror.cor:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-measurementerror.cor:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_measurementerror_cor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_measurementerror_cor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_measurementerror_cor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MeasurementError.cor)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rnorm
    library(MeasurementError.cor)
    exp <- matrix(abs(rnorm(100,1000,20)),ncol=10)
    se <- matrix(abs(rnorm(100,50,5)),ncol=10)
    cor.me.vector(exp[1,],se[1,],exp[2,],se[2,])
    cor.me.matrix(exp,se)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_measurementerror_cor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_measurementerror_cor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_measurementerror_cor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEASUREMENTERROR_COR:", paste0("    measurementerror_cor: ", packageVersion("MeasurementError.cor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_measurementerror_cor_results.csv
    touch ${prefix}_measurementerror_cor_output.rds
    echo "BIOC_MEASUREMENTERROR_COR:" > versions.yml
    echo "    measurementerror_cor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEASUREMENTERROR_COR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEASUREMENTERROR_COR(ch_input)

    emit:
    results  = BIOC_MEASUREMENTERROR_COR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEASUREMENTERROR_COR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEASUREMENTERROR_COR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEASUREMENTERROR_COR.out.versions  // channel: path(versions.yml)
}
