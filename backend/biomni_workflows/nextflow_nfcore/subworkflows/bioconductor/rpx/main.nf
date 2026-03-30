#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rpx
// The rpx package implements an interface to proteomics data submitted to the ProteomeXchange consorti
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rpx/inst/doc/rpx.R
// Upstream  : BiocStyle, Biostrings
// Downstream: none
//
// Install: BiocManager::install("rpx")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RPX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rpx"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rpx:2.14.1--r44_0' :
        'quay.io/biocontainers/bioconductor-rpx:2.14.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rpx_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rpx_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rpx_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PXDataset)
    library(jsonlite)

    # --- P X Dataset [] ---
    # Key functions: PXDataset
    library("rpx")
    px <- PXDataset(id)
    # --- pxget [] ---
    # Key functions: pxget
    f <- pxget(px, "F063721.dat-mztab.txt")
    # --- read A A String Set [] ---
    # Key functions: readAAStringSet
    library("Biostrings")
    readAAStringSet(f)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rpx_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rpx_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rpx_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RPX:", paste0("    rpx: ", packageVersion("rpx"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rpx_results.csv
    touch ${prefix}_rpx_output.rds
    echo "BIOC_RPX:" > versions.yml
    echo "    rpx: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RPX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RPX(ch_input)

    emit:
    results  = BIOC_RPX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RPX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RPX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RPX.out.versions  // channel: path(versions.yml)
}
