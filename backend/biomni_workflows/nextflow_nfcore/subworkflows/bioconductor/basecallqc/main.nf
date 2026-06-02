#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: basecallQC
// The basecallQC package provides tools to work with Illumina bcl2Fastq (versions >= 2.1.7) software.P
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/basecallQC/inst/doc/basecallQC.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("basecallQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASECALLQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-basecallqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-basecallqc:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-basecallqc:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_basecallqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_basecallqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_basecallqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BCL2FastQparams)
    library(jsonlite)

    # --- Dir analysis [] ---
    # Key functions: dir, BCL2FastQparams, validateBCLSheet, createBasemasks, createBCLcommand, basecallQC, baseCallMetrics, demultiplexMetrics
    fileLocations <- system.file("extdata",package="basecallQC")
    runXML <- dir(fileLocations,pattern="runParameters.xml",full.names=TRUE)
    config <- dir(fileLocations,pattern="config.ini",full.names=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_basecallqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_basecallqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_basecallqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASECALLQC:", paste0("    basecallqc: ", packageVersion("basecallQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basecallqc_results.csv
    touch ${prefix}_basecallqc_output.rds
    echo "BIOC_BASECALLQC:" > versions.yml
    echo "    basecallqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BASECALLQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BASECALLQC(ch_input)

    emit:
    results  = BIOC_BASECALLQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BASECALLQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BASECALLQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BASECALLQC.out.versions  // channel: path(versions.yml)
}
