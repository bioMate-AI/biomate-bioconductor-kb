#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TileDBArray
// Implements a DelayedArray backend for reading and writing dense or sparse arrays in the TileDB forma
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TileDBArray/inst/doc/userguide.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("TileDBArray")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TILEDBARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tiledbarray"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tiledbarray:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tiledbarray:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tiledbarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tiledbarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tiledbarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TileDBArray)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rnorm, writeTileDBArray
    ---------------------------------------------------------------------
    X <- matrix(rnorm(1000), ncol=10)
    library(TileDBArray)
    writeTileDBArray(X)
    # --- Rsparsematrix [] ---
    # Key functions: rsparsematrix, writeTileDBArray
    ---------------------------------------------------------------------
    Y <- Matrix::rsparsematrix(1000, 1000, density=0.01)
    writeTileDBArray(Y)
    # --- Writetiledbarray [] ---
    # Key functions: writeTileDBArray
    ---------------------------------------------------------------------
    writeTileDBArray(Y > 0)
    # --- Rownames [] ---
    # Key functions: writeTileDBArray
    ---------------------------------------------------------------------
    rownames(X) <- sprintf("GENE_%i", seq_len(nrow(X)))
    colnames(X) <- sprintf("SAMP_%i", seq_len(ncol(X)))
    writeTileDBArray(X)
    # --- Colsums [] ---
    # Key functions: colSums, runif
    ---------------------------------------------------------------------
    colSums(out)
    out %*% runif(ncol(out))
    # --- Matrix [] ---
    # Key functions: rnorm, tempfile, writeTileDBArray
    ---------------------------------------------------------------------
    X <- matrix(rnorm(1000), ncol=10)
    path <- tempfile()
    writeTileDBArray(X, path=path, attr="WHEE")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tiledbarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tiledbarray_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tiledbarray_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TILEDBARRAY:", paste0("    tiledbarray: ", packageVersion("TileDBArray"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tiledbarray_results.csv
    touch ${prefix}_tiledbarray_output.rds
    echo "BIOC_TILEDBARRAY:" > versions.yml
    echo "    tiledbarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TILEDBARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TILEDBARRAY(ch_input)

    emit:
    results  = BIOC_TILEDBARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TILEDBARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TILEDBARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TILEDBARRAY.out.versions  // channel: path(versions.yml)
}
