#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEE
// Create an interactive Shiny-based graphical user interface for exploring data stored in SummarizedEx
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEE/inst/doc/basic.R
// Upstream  : TENxPBMCData, scRNAseq, scater
// Downstream: iSEEde, iSEEhex, iSEEpathways, iSEEtree, iSEEu
//
// Install: BiocManager::install("iSEE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isee"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isee:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isee:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isee_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isee_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isee_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ReprocessedAllenData)
    library(jsonlite)

    # --- example [] ---
    # Key functions: example
    example(iSEE, ask=FALSE)
    # --- Reprocessed Allen Data [] ---
    # Key functions: ReprocessedAllenData
    library(scRNAseq)
    sce <- ReprocessedAllenData(assays = "tophat_counts")   # specifying the assays to speed up the example
    # --- colData sce [] ---
    # Key functions: logNormCounts
    colnames(colData(sce))
    library(scater)
    sce <- logNormCounts(sce, exprs_values="tophat_counts")
    # --- Run PCA [] ---
    # Key functions: runPCA, runTSNE, reducedDimNames, rowData
    set.seed(1000)
    sce <- runPCA(sce)
    sce <- runTSNE(sce)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isee_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isee_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isee_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEE:", paste0("    isee: ", packageVersion("iSEE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isee_results.csv
    touch ${prefix}_isee_output.rds
    echo "BIOC_ISEE:" > versions.yml
    echo "    isee: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEE(ch_input)

    emit:
    results  = BIOC_ISEE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEE.out.versions  // channel: path(versions.yml)
}
