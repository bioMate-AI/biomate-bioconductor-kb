#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metagenomeSeq
// metagenomeSeq is designed to determine features (be it Operational Taxanomic Unit (OTU), species, et
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metagenomeSeq/inst/doc/fitTimeSeries.R
// Upstream  : biomformat, gss, interactiveDisplay
// Downstream: microbiomeExplorer, etec16s
//
// Install: BiocManager::install("metagenomeSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAGENOMESEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metagenomeseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metagenomeseq:1.48.1--r44_0' :
        'quay.io/biocontainers/bioconductor-metagenomeseq:1.48.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metagenomeseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metagenomeseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metagenomeseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metagenomeSeq)
    library(jsonlite)

    # --- Time Series Analysis [] ---
    # Key functions: fitTimeSeries
    res1 <- fitTimeSeries(
        obj = obj,
        feature = 1,
        class = "class",
        time = "time",
        id = "sampleID",
        B = 10,
        norm = FALSE,
        log = FALSE
    )


    # --- Time Series Visualization [] ---
    # Key functions: plotClassTimeSeries, plotTimeSeries
    classInfo <- factor(res1$data$class)
    plotClassTimeSeries(
        res1,
        pch = 21,
        bg = classInfo
    )
    plotTimeSeries(res1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metagenomeseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metagenomeseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metagenomeseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METAGENOMESEQ:", paste0("    metagenomeseq: ", packageVersion("metagenomeSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metagenomeseq_results.csv
    touch ${prefix}_metagenomeseq_output.rds
    echo "BIOC_METAGENOMESEQ:" > versions.yml
    echo "    metagenomeseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METAGENOMESEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METAGENOMESEQ(ch_input)

    emit:
    results  = BIOC_METAGENOMESEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METAGENOMESEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METAGENOMESEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METAGENOMESEQ.out.versions  // channel: path(versions.yml)
}
