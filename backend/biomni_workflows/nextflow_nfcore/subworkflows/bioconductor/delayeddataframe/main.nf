#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DelayedDataFrame
// Based on the standard DataFrame metaphor, we are trying to implement the feature of delayed operatio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DelayedDataFrame/inst/doc/DelayedDataFrame.R
// Upstream  : GDSArray
// Downstream: none
//
// Install: BiocManager::install("DelayedDataFrame")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DELAYEDDATAFRAME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-delayeddataframe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-delayeddataframe:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-delayeddataframe:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_delayeddataframe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_delayeddataframe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_delayeddataframe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DelayedDataFrame)
    library(GDSArray)
    library(jsonlite)

    # --- seq Example File Name [] ---
    # Key functions: seqExampleFileName, gdsnodes, GDSArray
    library(GDSArray)
    file <- SeqArray::seqExampleFileName("gds")
    gdsnodes(file)
    # --- Delayed Data Frame [] ---
    # Key functions: DelayedDataFrame
    ddf <- DelayedDataFrame(varid, DP)  ## only accommodate 1D GDSArrays with same length
    # --- lazy Index [] ---
    # Key functions: lazyIndex
    lazyIndex(ddf)
    nrow(ddf)
    rownames(ddf)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_delayeddataframe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_delayeddataframe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_delayeddataframe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DELAYEDDATAFRAME:", paste0("    delayeddataframe: ", packageVersion("DelayedDataFrame"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delayeddataframe_results.csv
    touch ${prefix}_delayeddataframe_output.rds
    echo "BIOC_DELAYEDDATAFRAME:" > versions.yml
    echo "    delayeddataframe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DELAYEDDATAFRAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DELAYEDDATAFRAME(ch_input)

    emit:
    results  = BIOC_DELAYEDDATAFRAME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DELAYEDDATAFRAME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DELAYEDDATAFRAME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DELAYEDDATAFRAME.out.versions  // channel: path(versions.yml)
}
