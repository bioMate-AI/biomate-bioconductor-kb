#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nnNorm
// This package allows to detect and correct for spatial and intensity biases with two-channel microarr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nnNorm/inst/doc/nnNorm.R
// Upstream  : marray
// Downstream: none
//
// Install: BiocManager::install("nnNorm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NNNORM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nnnorm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nnnorm:2.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nnnorm:2.70.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nnnorm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nnnorm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nnnorm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(nnNorm)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(marray)
    data(swirl)
    # --- Manormnn [] ---
    # Key functions: maNormNN
    library(nnNorm)
    swirl_n<-maNormNN(swirl[,1:2])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nnnorm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nnnorm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nnnorm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NNNORM:", paste0("    nnnorm: ", packageVersion("nnNorm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nnnorm_results.csv
    touch ${prefix}_nnnorm_output.rds
    echo "BIOC_NNNORM:" > versions.yml
    echo "    nnnorm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NNNORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NNNORM(ch_input)

    emit:
    results  = BIOC_NNNORM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NNNORM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NNNORM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NNNORM.out.versions  // channel: path(versions.yml)
}
