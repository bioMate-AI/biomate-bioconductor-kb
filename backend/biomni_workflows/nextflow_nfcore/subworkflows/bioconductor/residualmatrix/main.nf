#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ResidualMatrix
// Provides delayed computation of a matrix of residuals after fitting a linear model to each column of
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ResidualMatrix/inst/doc/ResidualMatrix.R
// Upstream  : Matrix
// Downstream: none
//
// Install: BiocManager::install("ResidualMatrix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RESIDUALMATRIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-residualmatrix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-residualmatrix:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-residualmatrix:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_residualmatrix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_residualmatrix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_residualmatrix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ResidualMatrix)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: gl, rsparsematrix, ResidualMatrix
    ---------------------------------------------------------------------
    design <- model.matrix(~gl(5, 10000))
    # Making up a large-ish sparse matrix.
    library(Matrix)
    set.seed(100)
    # --- Hist [] ---
    # Key functions: rowSums
    ---------------------------------------------------------------------
    hist(rowSums(resids))
    # --- Matrix [] ---
    # Key functions: gl, runif
    ---------------------------------------------------------------------
    design2 <- model.matrix(~gl(2, 10000))
    design2 <- cbind(design2, BAD=runif(nrow(design2)))
    colnames(design2)
    # --- Rsparsematrix [] ---
    # Key functions: rsparsematrix, ResidualMatrix
    ---------------------------------------------------------------------
    # Making up another large-ish sparse matrix.
    y0 <- rsparsematrix(nrow(design2), 30000, 0.01)
    resid2 <- ResidualMatrix(y0, design2, keep=1:2)
    resid2
    # --- Gl [] ---
    # Key functions: gl, rnorm, ResidualMatrix
    ---------------------------------------------------------------------
    batches <- gl(3, 1000)
    controls <- c(1:100, 1:100+1000, 1:100+2000)
    y <- matrix(rnorm(30000), nrow=3000)
    resid3 <- ResidualMatrix(y, design=model.matrix(~batches), restrict=controls)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_residualmatrix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_residualmatrix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_residualmatrix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RESIDUALMATRIX:", paste0("    residualmatrix: ", packageVersion("ResidualMatrix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_residualmatrix_results.csv
    touch ${prefix}_residualmatrix_output.rds
    echo "BIOC_RESIDUALMATRIX:" > versions.yml
    echo "    residualmatrix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RESIDUALMATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RESIDUALMATRIX(ch_input)

    emit:
    results  = BIOC_RESIDUALMATRIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RESIDUALMATRIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RESIDUALMATRIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RESIDUALMATRIX.out.versions  // channel: path(versions.yml)
}
