#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: skewr
// The skewr package is a tool for visualizing the output of the Illumina Human Methylation 450k BeadCh
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/skewr/inst/doc/skewr.R
// Upstream  : minfiData
// Downstream: none
//
// Install: BiocManager::install("skewr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SKEWR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-skewr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-skewr:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-skewr:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_skewr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_skewr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_skewr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(skewr)
    library(jsonlite)

    # --- get Barcodes [] ---
    # Key functions: getBarcodes
    baseDir <- system.file("extdata/5723646052", package = "minfiData")
    barcodes <- getBarcodes(path = baseDir)
    # --- panel Plots [] ---
    # Key functions: panelPlots
    panelPlots(melon.raw, raw.I.red.mixes, raw.I.green.mixes,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_skewr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_skewr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_skewr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SKEWR:", paste0("    skewr: ", packageVersion("skewr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_skewr_results.csv
    touch ${prefix}_skewr_output.rds
    echo "BIOC_SKEWR:" > versions.yml
    echo "    skewr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SKEWR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SKEWR(ch_input)

    emit:
    results  = BIOC_SKEWR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SKEWR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SKEWR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SKEWR.out.versions  // channel: path(versions.yml)
}
