#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ReadqPCR
// The package provides functions to read raw RT-qPCR data of different platforms.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ReadqPCR/inst/doc/ReadqPCR.R
// Upstream  : none
// Downstream: NormqPCR
//
// Install: BiocManager::install("ReadqPCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_READQPCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-readqpcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-readqpcr:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-readqpcr:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_readqpcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_readqpcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_readqpcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ReadqPCR)
    library(jsonlite)


    # --- Cycles Set [] ---
    # Key functions: getClass
    cycData
    ## Information about class CyclesSet
    getClass("CyclesSet")

    # --- Merge [] ---
    # Key functions: phenoData, pData, varMetadata
    cycData1 <- merge(cycData, samInfo)
    ## Extended pheno data
    phenoData(cycData1)
    head(pData(cycData1))
    varMetadata(phenoData(cycData1))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_readqpcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_readqpcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_readqpcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_READQPCR:", paste0("    readqpcr: ", packageVersion("ReadqPCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_readqpcr_results.csv
    touch ${prefix}_readqpcr_output.rds
    echo "BIOC_READQPCR:" > versions.yml
    echo "    readqpcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_READQPCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_READQPCR(ch_input)

    emit:
    results  = BIOC_READQPCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_READQPCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_READQPCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_READQPCR.out.versions  // channel: path(versions.yml)
}
