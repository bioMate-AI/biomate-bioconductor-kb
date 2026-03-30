#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chihaya
// Saves the delayed operations of a DelayedArray to a HDF5 file. This enables efficient recovery of th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chihaya/inst/doc/userguide.R
// Upstream  : BiocStyle, DelayedArray, HDF5Array, Matrix
// Downstream: none
//
// Install: BiocManager::install("chihaya")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIHAYA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chihaya"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chihaya:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chihaya:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chihaya_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chihaya_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chihaya_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DelayedArray)
    library(HDF5Array)
    library(jsonlite)

    # --- Delayedarray [] ---
    # Key functions: DelayedArray, runif, showtree
    ---------------------------------------------------------------------
    library(DelayedArray)
    x <- DelayedArray(matrix(runif(1000), ncol=10))
    x <- x[11:15,] / runif(5)
    x <- log2(x + 1)
    # --- Loaddelayed [] ---
    # Key functions: loadDelayed
    ---------------------------------------------------------------------
    y <- loadDelayed(tmp)
    y
    # --- Rsparsematrix [] ---
    # Key functions: rsparsematrix, DelayedArray, runif, tempfile, saveDelayed, h5ls, info
    ---------------------------------------------------------------------
    library(Matrix)
    x <- rsparsematrix(1000, 1000, density=0.01)
    x <- DelayedArray(x) + runif(1000)
    tmp <- tempfile(fileext=".h5")
    # --- Access INFO field from VCF [] ---
    # Key functions: HDF5Array, tempfile, saveDelayed, h5ls, info, loadDelayed
    ---------------------------------------------------------------------
    library(HDF5Array)
    test <- HDF5Array(tmp2, "data")
    stuff <- log2(test + 1)
    stuff

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chihaya_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chihaya_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chihaya_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIHAYA:", paste0("    chihaya: ", packageVersion("chihaya"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chihaya_results.csv
    touch ${prefix}_chihaya_output.rds
    echo "BIOC_CHIHAYA:" > versions.yml
    echo "    chihaya: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIHAYA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIHAYA(ch_input)

    emit:
    results  = BIOC_CHIHAYA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIHAYA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIHAYA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIHAYA.out.versions  // channel: path(versions.yml)
}
