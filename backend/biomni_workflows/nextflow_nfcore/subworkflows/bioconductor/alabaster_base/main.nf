#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.base
// Save Bioconductor data structures into file artifacts, and load them back into memory. This is a mor
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.base/inst/doc/userguide.R
// Upstream  : BiocStyle, Matrix, S4Vectors
// Downstream: alabaster, alabaster.bumpy, alabaster.mae, alabaster.matrix, alabaster.ranges
//
// Install: BiocManager::install("alabaster.base")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_BASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_base"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alabaster.base:1.6.1--r44_0' :
        'quay.io/biocontainers/bioconductor-alabaster.base:1.6.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_base_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_base_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_base_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(I)
    library(jsonlite)

    # --- Dataframe [] ---
    # Key functions: DataFrame
    ---------------------------------------------------------------------
    library(S4Vectors)
    df <- DataFrame(X=1:10, Y=letters[1:10])
    df
    # --- Readobject [] ---
    # Key functions: readObject
    ---------------------------------------------------------------------
    readObject(tmp)
    # --- Validateobject [] ---
    # Key functions: validateObject
    ---------------------------------------------------------------------
    validateObject(tmp)
    # --- Dataframe [] ---
    # Key functions: DataFrame, factor, I, runif, rnorm, tempfile, saveObject, files
    ---------------------------------------------------------------------
    # Creating a nested DF to be a little spicy:
    df2 <- DataFrame(Z=factor(1:5), AA=I(DataFrame(B=runif(5), C=rnorm(5))))
    tmp <- tempfile()
    meta2 <- saveObject(df2, tmp)
    # --- Setmethod [] ---
    # Key functions: setMethod, create, DataFrame, csv, path, write
    ---------------------------------------------------------------------
    library(Matrix)
    # --- Function [] ---
    # Key functions: path, sparseMatrix, registerReadObjectFunction
    ---------------------------------------------------------------------
    # --- Sparsematrix [] ---
    # Key functions: sparseMatrix, runif, tempfile, saveObject, files, readObject
    ---------------------------------------------------------------------
    # --- Setgeneric [] ---
    # Key functions: setGeneric, standardGeneric, path, write, toJSON, setMethod, saveObject
    ---------------------------------------------------------------------
    # --- Function [] ---
    # Key functions: altSaveObjectFunction, exit, altSaveObject, DataFrame, factor, I, runif
    ---------------------------------------------------------------------
    # Create a friendly user-visible function to handle the generic override; this
    # is reversed on function exit to avoid interfering with other applications.
    # --- Altreadobject [] ---
    # Key functions: altReadObject, null, readObjectFile, fromJSON, path
    ---------------------------------------------------------------------
    # Defining the override for altReadObject().

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alabaster_base_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alabaster_base_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alabaster_base_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_BASE:", paste0("    alabaster_base: ", packageVersion("alabaster.base"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_base_results.csv
    touch ${prefix}_alabaster_base_output.rds
    echo "BIOC_ALABASTER_BASE:" > versions.yml
    echo "    alabaster_base: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_BASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_BASE(ch_input)

    emit:
    results  = BIOC_ALABASTER_BASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_BASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_BASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_BASE.out.versions  // channel: path(versions.yml)
}
