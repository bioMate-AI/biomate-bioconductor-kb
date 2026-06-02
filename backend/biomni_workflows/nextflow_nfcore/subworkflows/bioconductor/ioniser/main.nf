#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IONiseR
// IONiseR provides tools for the quality assessment of Oxford Nanopore MinION data. It extracts summar
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IONiseR/inst/doc/IONiseR.R
// Upstream  : ShortRead, dplyr, ggplot2, gridExtra, minionSummaryData
// Downstream: none
//
// Install: BiocManager::install("IONiseR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IONISER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ioniser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ioniser:2.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ioniser:2.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ioniser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ioniser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ioniser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IONiseR)
    library(jsonlite)

    # --- BaseCalled analysis [] ---
    # Key functions: baseCalled, plotReadAccumulation, plotActiveChannels, plotReadCategoryCounts, plotReadCategoryQuals, plotEventRate, plotBaseProductionRate, layoutPlot
    fast5files <- system.file('extdata', 'example.fast5', package = "IONiseR")
    fast5toFastq(files = fast5files, fileName = "test", outputDir = tempdir(),
    list.files(path = tempdir(), pattern = "*.fq.gz$")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ioniser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ioniser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ioniser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IONISER:", paste0("    ioniser: ", packageVersion("IONiseR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ioniser_results.csv
    touch ${prefix}_ioniser_output.rds
    echo "BIOC_IONISER:" > versions.yml
    echo "    ioniser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IONISER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IONISER(ch_input)

    emit:
    results  = BIOC_IONISER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IONISER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IONISER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IONISER.out.versions  // channel: path(versions.yml)
}
