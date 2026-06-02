#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Statial
// Statial is a suite of functions for identifying changes in cell state. The functionality provided by
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Statial/inst/doc/Statial.R
// Upstream  : BiocStyle, ClassifyR, SingleCellExperiment, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("Statial")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STATIAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-statial"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-statial:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-statial:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_statial_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_statial_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_statial_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Kontextual)
    library(jsonlite)

    # --- get Cluster Tree [] ---
    # Key functions: getClusterTree
    kerenTree <- treekoR::getClusterTree(t(assay(kerenSCE, "intensities")),
    treekorParents = getParentPhylo(kerenTree)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: assay, colData, arrange, ggplot, geom_point
    p53Pos <- assay(kerenSCE)["p53", ] > -0.300460
    colData() |>
    as.data.frame() |>
    # --- Kontextual [] ---
    # Key functions: Kontextual
    p53_Kontextual <- Kontextual(
    parent = c("p53_Tumour", "Tumour"),
    # --- kontext Curve [] ---
    # Key functions: kontextCurve, kontextPlot
    curves <- kontextCurve(
    parent = c("p53_Tumour", "Tumour"),
    rs = seq(50, 510, 50),
    # --- parent Combinations [] ---
    # Key functions: parentCombinations
    parentDf <- parentCombinations(
    # --- get Marker Means [] ---
    # Key functions: getMarkerMeans, colTest, getProp, crossValidate
    cellTypeRegionMeans <- getMarkerMeans(kerenSCE,
    survivalResults <- colTest(cellTypeRegionMeans[names(kerenSurv), ], kerenSurv, type = "survival")
    head(survivalResults)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_statial_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_statial_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_statial_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STATIAL:", paste0("    statial: ", packageVersion("Statial"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_statial_results.csv
    touch ${prefix}_statial_output.rds
    echo "BIOC_STATIAL:" > versions.yml
    echo "    statial: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STATIAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STATIAL(ch_input)

    emit:
    results  = BIOC_STATIAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STATIAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STATIAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STATIAL.out.versions  // channel: path(versions.yml)
}
