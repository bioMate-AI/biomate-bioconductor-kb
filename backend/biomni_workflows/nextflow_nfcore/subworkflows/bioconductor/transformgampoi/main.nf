#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: transformGamPoi
// Variance-stabilizing transformations help with the analysis of heteroskedastic data (i.e., data wher
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/transformGamPoi/inst/doc/transformGamPoi.R
// Upstream  : MatrixGenerics
// Downstream: none
//
// Install: BiocManager::install("transformGamPoi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRANSFORMGAMPOI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-transformgampoi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-transformgampoi:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-transformgampoi:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_transformgampoi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_transformgampoi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_transformgampoi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(transformGamPoi)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, par
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    set.seed(1)
    par(cex = 1.5)

    # --- Load Data [] ---
    # Key functions: TENxPBMCData, sample, assay, rowMeans2, counts, rowVars, pbmc4k
    # Load the 'TENxPBMCData' as a SingleCellExperiment object
    sce <- TENxPBMCData::TENxPBMCData("pbmc4k")
    # Subset the data to 1,000 x 500 random genes and cells
    sce <- sce[sample(nrow(sce), 1000), sample(ncol(sce), 500)]

    ## -----------------------------------------------------------------------------
    assay(sce, "counts")[1:10, 1:5]

    ## -----------------------------------------------------------------------------
    library(MatrixGenerics)
    # Exclude genes where all counts are zero
    sce <- sce[rowMeans2(counts(sce)) > 0, ]
    gene_means <- rowMeans2(counts(sce))
    gene_var <- rowVars(counts(sce))
    plot(gene_means, gene_var, log = "xy", main = "Log-log scatter plot of mean vs variance")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_transformgampoi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_transformgampoi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_transformgampoi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRANSFORMGAMPOI:", paste0("    transformgampoi: ", packageVersion("transformGamPoi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transformgampoi_results.csv
    touch ${prefix}_transformgampoi_output.rds
    echo "BIOC_TRANSFORMGAMPOI:" > versions.yml
    echo "    transformgampoi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRANSFORMGAMPOI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_TRANSFORMGAMPOI(ch_input)

    emit:
    results  = BIOC_TRANSFORMGAMPOI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRANSFORMGAMPOI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRANSFORMGAMPOI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRANSFORMGAMPOI.out.versions  // channel: path(versions.yml)
}
