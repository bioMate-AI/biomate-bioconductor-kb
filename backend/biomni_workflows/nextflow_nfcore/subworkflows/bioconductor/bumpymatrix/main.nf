#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BumpyMatrix
// Implements the BumpyMatrix class and several subclasses for holding non-scalar objects in each entry
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BumpyMatrix/inst/doc/BumpyMatrix.R
// Upstream  : BiocStyle, S4Vectors
// Downstream: alabaster.bumpy
//
// Install: BiocManager::install("BumpyMatrix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUMPYMATRIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bumpymatrix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bumpymatrix:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bumpymatrix:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bumpymatrix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bumpymatrix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bumpymatrix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(jsonlite)

    # --- Dataframe [] ---
    # Key functions: DataFrame, rnorm, sample
    ---------------------------------------------------------------------
    library(S4Vectors)
    # --- Splitasbumpymatrix [] ---
    # Key functions: splitAsBumpyMatrix
    ---------------------------------------------------------------------
    library(BumpyMatrix)
    mat <- splitAsBumpyMatrix(df[,c("x", "y")], row=df$gene, column=df$cell)
    mat
    mat[1,1][[1]]
    # --- Dim [] ---
    # Key functions: dimnames
    ---------------------------------------------------------------------
    dim(mat)
    dimnames(mat)
    rbind(mat, mat)
    cbind(mat, mat)
    # --- Pmax [] ---
    # Key functions: pmax
    ---------------------------------------------------------------------
    pmax(out.x, out.y)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bumpymatrix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bumpymatrix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bumpymatrix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUMPYMATRIX:", paste0("    bumpymatrix: ", packageVersion("BumpyMatrix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bumpymatrix_results.csv
    touch ${prefix}_bumpymatrix_output.rds
    echo "BIOC_BUMPYMATRIX:" > versions.yml
    echo "    bumpymatrix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUMPYMATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUMPYMATRIX(ch_input)

    emit:
    results  = BIOC_BUMPYMATRIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUMPYMATRIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUMPYMATRIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUMPYMATRIX.out.versions  // channel: path(versions.yml)
}
