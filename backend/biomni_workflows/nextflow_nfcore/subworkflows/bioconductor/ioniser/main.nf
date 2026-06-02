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

    # --- Read Quality Control and Accumulation [] ---
    # Key functions: plotReadAccumulation, plotActiveChannels, plotReadCategoryCounts, plotReadCategoryQuals
    p1 <- plotReadAccumulation(minionSummaryData::s.typhi.rep1)
    p2 <- plotActiveChannels(minionSummaryData::s.typhi.rep1)
    p3 <- plotReadCategoryCounts(minionSummaryData::s.typhi.rep1)
    p4 <- plotReadCategoryQuals(minionSummaryData::s.typhi.rep1)


    # --- Spatial Channel Activity Analysis [] ---
    # Key functions: layoutPlot, channelActivityPlot, eventData
    p1 <- layoutPlot(minionSummaryData::s.typhi.rep1, attribute = "nreads")
    p2 <- layoutPlot(minionSummaryData::s.typhi.rep1, attribute = "kb")
    z_scale <- dplyr::select(
        eventData(minionSummaryData::s.typhi.rep3),
        id,
        median_signal
    )
    p3 <- channelActivityPlot(minionSummaryData::s.typhi.rep3, zScale = z_scale)


    # --- K-mer Frequency Correlation [] ---
    # Key functions: plotKmerFrequencyCorrelation
    kmer_corr <- plotKmerFrequencyCorrelation(
        minionSummaryData::s.typhi.rep3,
        only2D = FALSE
    )

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
