#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ropls
// Latent variable modeling with Principal Component Analysis (PCA) and Partial Least Squares (PLS) are
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ropls/inst/doc/ropls-vignette.R
// Upstream  : Biobase, MultiAssayExperiment, MultiDataSet, SummarizedExperiment, phenomis
// Downstream: none
//
// Install: BiocManager::install("ropls")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ROPLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ropls"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ropls:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ropls:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ropls_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ropls_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ropls_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Create SummarizedExperiment [] ---
    # Key functions: SummarizedExperiment, listToMap
    library(MultiAssayExperiment)
    experiment.ls <- list()
    sampleMap.ls <- list()
    # --- Sample metadata inspection [] ---
    # Key functions: view, getSubsetVi, predict, plot_score, colData, writing, sample, opls
    Preparing the data (matrix) and sample and variable metadata (data frames):
    data(sacurine, package = "ropls")
    Creating the SummarizedExperiment (package SummarizedExperiment)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ropls_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ropls_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ropls_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ROPLS:", paste0("    ropls: ", packageVersion("ropls"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ropls_results.csv
    touch ${prefix}_ropls_output.rds
    echo "BIOC_ROPLS:" > versions.yml
    echo "    ropls: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ROPLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ROPLS(ch_input)

    emit:
    results  = BIOC_ROPLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ROPLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ROPLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ROPLS.out.versions  // channel: path(versions.yml)
}
