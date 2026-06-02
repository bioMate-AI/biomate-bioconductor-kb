#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scater
// A collection of tools for doing various analyses of single-cell RNA-seq gene expression data, with a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scater/inst/doc/overview.R
// Upstream  : scRNAseq
// Downstream: netSmooth, OSCA.advanced, OSCA.basic, OSCA.intro, OSCA.multisample
//
// Install: BiocManager::install("scater")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCATER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scater"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scater:1.34.1--r44_0' :
        'quay.io/biocontainers/bioconductor-scater:1.34.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scater_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scater_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scater_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Log-normalize count data [] ---
    # Key functions: plotHighestExprs, logNormCounts, getVarianceExplained, plotExplanatoryVariables
    plotHighestExprs(example_sce, exprs_values = "counts")
    example_sce <- logNormCounts(example_sce)
    # --- Run PCA [] ---
    # Key functions: plotExpression, runPCA, runTSNE, runUMAP, plotPCA
    plotExpression(example_sce, rownames(example_sce)[1:6])
    example_sce <- runPCA(example_sce)
    str(reducedDim(example_sce, "PCA"))
    # --- PCA plot of sample distances [] ---
    # Key functions: plotPCA
    plotPCA(example_sce, colour_by="Mog")
    # --- ZeiselBrainData analysis [] ---
    # Key functions: ZeiselBrainData, addPerCellQC, plotColData, plotExpression, plotReducedDim, plotTSNE
    plotColData(example_sce, x = "sum", y="subsets_Mito_percent",
    other_fields="tissue") + facet_wrap(~tissue)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scater_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scater_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scater_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCATER:", paste0("    scater: ", packageVersion("scater"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scater_results.csv
    touch ${prefix}_scater_output.rds
    echo "BIOC_SCATER:" > versions.yml
    echo "    scater: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCATER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCATER(ch_input)

    emit:
    results  = BIOC_SCATER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCATER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCATER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCATER.out.versions  // channel: path(versions.yml)
}
