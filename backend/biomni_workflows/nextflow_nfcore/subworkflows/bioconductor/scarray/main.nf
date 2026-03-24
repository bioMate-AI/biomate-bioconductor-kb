#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SCArray
// Provides large-scale single-cell omics data manipulation using Genomic Data Structure (GDS) files. I
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SCArray/inst/doc/SCArray.R
// Upstream  : Matrix, SingleCellExperiment, scater, scuttle
// Downstream: SCArray.sat
//
// Install: BiocManager::install("SCArray")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scarray"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scarray:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scarray:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DelayedMatrix)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: int, rpois, scConvGDS
    ---------------------------------------------------------------------------------------------------
    library(Matrix)
    cnt <- matrix(0, nrow=4, ncol=8)
    set.seed(100); cnt[sample.int(length(cnt), 8)] <- rpois(8, 4)
    (cnt <- as(cnt, "sparseMatrix"))
    # --- Package [] ---
    # Key functions: package, scExperiment, DelayedMatrix, assays, colData, rowData
    ---------------------------------------------------------------------------------------------------
    # a GDS file in the SCArray package
    (fn <- system.file("extdata", "example.gds", package="SCArray"))
    # load a SingleCellExperiment object from the file
    sce <- scExperiment(fn)
    # --- Assays [] ---
    # Key functions: assays
    ---------------------------------------------------------------------------------------------------
    cnt <- assays(sce)$counts
    logcnt <- log2(cnt + 1)
    logcnt
    # --- Colmeans [] ---
    # Key functions: colMeans, rowMeans, scRowMeanVar
    ---------------------------------------------------------------------------------------------------
    col_mean <- colMeans(logcnt)
    str(col_mean)
    row_mean <- rowMeans(logcnt)
    str(row_mean)
    # --- Scrunpca [] ---
    # Key functions: scRunPCA
    ---------------------------------------------------------------------------------------------------
    sce <- scRunPCA(sce)
    # --- Rowmeans [] ---
    # Key functions: rowMeans
    ---------------------------------------------------------------------------------------------------
    options(SCArray.verbose=TRUE)
    m <- rowMeans(logcnt)
    str(m)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scarray_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scarray_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCARRAY:", paste0("    scarray: ", packageVersion("SCArray"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scarray_results.csv
    touch ${prefix}_scarray_output.rds
    echo "BIOC_SCARRAY:" > versions.yml
    echo "    scarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCARRAY(ch_input)

    emit:
    results  = BIOC_SCARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCARRAY.out.versions  // channel: path(versions.yml)
}
