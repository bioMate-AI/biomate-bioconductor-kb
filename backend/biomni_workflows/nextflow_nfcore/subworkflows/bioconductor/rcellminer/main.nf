#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rcellminer
// The NCI-60 cancer cell line panel has been used over the course of several decades as an anti-cancer
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rcellminer/inst/doc/rcellminerUsage.R
// Upstream  : knitr, rcellminerData
// Downstream: none
//
// Install: BiocManager::install("rcellminer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCELLMINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcellminer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcellminer:2.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcellminer:2.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcellminer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcellminer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcellminer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rcellminer)
    library(jsonlite)

    # --- Expression matrix extraction [] ---
    # Key functions: searchForNscs, exprs, getMolDataMatrices, plotCellMiner, plotDrugSets, getFeatureAnnot, getDrugActivityData, removeMolDataType
    getFeatureAnnot() returns a named list of data frames with annotation data
    for drugs ("drug") and drug activity repeat experiments ("drugRepeat").
    drugAnnot <- getFeatureAnnot(rcellminerData::drugData)[["drug"]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcellminer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcellminer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcellminer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCELLMINER:", paste0("    rcellminer: ", packageVersion("rcellminer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcellminer_results.csv
    touch ${prefix}_rcellminer_output.rds
    echo "BIOC_RCELLMINER:" > versions.yml
    echo "    rcellminer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCELLMINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCELLMINER(ch_input)

    emit:
    results  = BIOC_RCELLMINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCELLMINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCELLMINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCELLMINER.out.versions  // channel: path(versions.yml)
}
