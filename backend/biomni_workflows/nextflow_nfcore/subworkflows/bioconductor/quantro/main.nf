#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: quantro
// A data-driven test for the assumptions of quantile normalization using raw data such as objects that
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/quantro/inst/doc/quantro.R
// Upstream  : doParallel, minfi
// Downstream: none
//
// Install: BiocManager::install("quantro")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUANTRO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-quantro"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-quantro:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-quantro:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_quantro_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_quantro_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_quantro_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(quantro)
    library(jsonlite)

    # --- Phenotype data inspection [] ---
    # Key functions: getBeta, pData, matdensity, matboxplot, quantro, registerDoParallel, quantroPlot


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_quantro_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_quantro_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_quantro_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUANTRO:", paste0("    quantro: ", packageVersion("quantro"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantro_results.csv
    touch ${prefix}_quantro_output.rds
    echo "BIOC_QUANTRO:" > versions.yml
    echo "    quantro: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUANTRO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QUANTRO(ch_input)

    emit:
    results  = BIOC_QUANTRO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUANTRO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUANTRO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUANTRO.out.versions  // channel: path(versions.yml)
}
