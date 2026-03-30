#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.matrix
// Save matrices, arrays and similar objects into file artifacts, and load them back into memory. This 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.matrix/inst/doc/userguide.R
// Upstream  : BiocStyle, Matrix
// Downstream: none
//
// Install: BiocManager::install("alabaster.matrix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_MATRIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_matrix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alabaster.matrix:1.6.1--r44_0' :
        'quay.io/biocontainers/bioconductor-alabaster.matrix:1.6.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_matrix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_matrix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_matrix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(alabaster.matrix)
    library(jsonlite)

    # --- Rsparsematrix [] ---
    # Key functions: rsparsematrix, tempfile, saveObject, files
    ---------------------------------------------------------------------
    library(Matrix)
    y <- rsparsematrix(1000, 100, density=0.05)
    library(alabaster.matrix)
    tmp <- tempfile()
    # --- Readobject [] ---
    # Key functions: readObject
    ---------------------------------------------------------------------
    roundtrip <- readObject(tmp)
    class(roundtrip)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alabaster_matrix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alabaster_matrix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alabaster_matrix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_MATRIX:", paste0("    alabaster_matrix: ", packageVersion("alabaster.matrix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_matrix_results.csv
    touch ${prefix}_alabaster_matrix_output.rds
    echo "BIOC_ALABASTER_MATRIX:" > versions.yml
    echo "    alabaster_matrix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_MATRIX(ch_input)

    emit:
    results  = BIOC_ALABASTER_MATRIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_MATRIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_MATRIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_MATRIX.out.versions  // channel: path(versions.yml)
}
