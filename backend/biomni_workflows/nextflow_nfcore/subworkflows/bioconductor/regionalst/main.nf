#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RegionalST
// This package analyze spatial transcriptomics data through cross-regional cell type-specific analysis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RegionalST/inst/doc/RegionalST.R
// Upstream  : BayesSpace, CARD, Matrix, ggplot2, gridExtra
// Downstream: none
//
// Install: BiocManager::install("RegionalST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONALST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regionalst"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regionalst:1.4.2--r44_0' :
        'quay.io/biocontainers/bioconductor-regionalst:1.4.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regionalst_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regionalst_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regionalst_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CARD_deconvolution)
    library(GetOneRadiusEntropy_withProp)
    library(ManualSelectCenter)
    library(PlotOneSelectedCenter)
    library(RankCenterByEntropy_withProp)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment
    library(Matrix)
    rowData <- read.csv("path/to/rowData.csv", stringsAsFactors=FALSE)
    colData <- read.csv("path/to/colData.csv", stringsAsFactors=FALSE, row.names=1)
    # --- Assay listing [] ---
    # Key functions: readVisium, spatialPreprocess, assays, createCARDObject, CARD_deconvolution, metadata, mySpatialPreprocess, GetOneRadiusEntropy_withProp
    thisID1 <- S4Vectors::metadata(example_sce)$selectCenters$selectID[1]
    thisRadius1 <- S4Vectors::metadata(example_sce)$selectCenters$selectRadius[1]
    OutRegRes1 <- RegionalST::FindRegionalCells(example_sce,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regionalst_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regionalst_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regionalst_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONALST:", paste0("    regionalst: ", packageVersion("RegionalST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regionalst_results.csv
    touch ${prefix}_regionalst_output.rds
    echo "BIOC_REGIONALST:" > versions.yml
    echo "    regionalst: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONALST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGIONALST(ch_input)

    emit:
    results  = BIOC_REGIONALST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONALST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONALST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONALST.out.versions  // channel: path(versions.yml)
}
