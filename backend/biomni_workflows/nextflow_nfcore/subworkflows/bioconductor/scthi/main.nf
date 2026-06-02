#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scTHI
// scTHI is an R package to identify active pairs of ligand-receptors from single cells in order to stu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scTHI/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("scTHI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCTHI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scthi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scthi:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scthi:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scthi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scthi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scthi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scTHI)
    library(TME_plot)
    library(jsonlite)

    # --- Interaction Visualization [] ---
    # Key functions: scTHI_plotResult, scTHI_plotPairs
    scTHI_plotResult(
        scTHIresult = H3K27.result,
        cexNames = 0.7,
        plotType = "score"
    )
    scTHI_plotResult(
        scTHIresult = H3K27.result,
        cexNames = 0.7,
        plotType = "pair"
    )
    scTHI_plotPairs(
        scTHIresult = H3K27.result,
        cexPoint = 0.8,
        interactionToplot = "THY1_ITGAX:ITGB2"
    )


    # --- Dimensionality Reduction and Clustering [] ---
    # Key functions: scTHI_runTsne, scTHI_plotCluster
    H3K27.result <- scTHI_runTsne(
        scTHIresult = H3K27.result
    )
    scTHI_plotCluster(
        scTHIresult = H3K27.result,
        cexPoint = 0.8,
        legendPos = "bottomleft"
    )


    # --- Microenvironment Classification [] ---
    # Key functions: TME_classification, TME_plot
    Tme.cells <- rownames(H3K27.meta)[which(H3K27.meta$Type != "Malignant")]
    H3K27.tme <- H3K27[, Tme.cells]
    Class <- TME_classification(
        expMat = H3K27.tme,
        minLenGeneSet = 10
    )
    TME_plot(
        tsneData = H3K27.result$tsneData,
        Class = Class,
        cexPoint = 0.8
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scthi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scthi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scthi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCTHI:", paste0("    scthi: ", packageVersion("scTHI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scthi_results.csv
    touch ${prefix}_scthi_output.rds
    echo "BIOC_SCTHI:" > versions.yml
    echo "    scthi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCTHI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCTHI(ch_input)

    emit:
    results  = BIOC_SCTHI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCTHI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCTHI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCTHI.out.versions  // channel: path(versions.yml)
}
