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


    # --- Load Data [] ---
    # Key functions: ioniser
    library(minionSummaryData)
    data(s.typhi.rep1)
    s.typhi.rep1

    # --- Extract Data1 [] ---
    # Key functions: baseCalled
    baseCalled(s.typhi.rep1)
    baseCalled(s.typhi.rep1[1:2])

    # --- Summary Plots1 [] ---
    # Key functions: plotReadAccumulation, plotActiveChannels, grid.arrange, plotReadCategoryCounts, plotReadCategoryQuals
    p1 <- plotReadAccumulation(s.typhi.rep1)
    p2 <- plotActiveChannels(s.typhi.rep1)
    grid.arrange(p1, p2, ncol = 2)
    p1 <- plotReadCategoryCounts(s.typhi.rep1)
    p2 <- plotReadCategoryQuals(s.typhi.rep1)
    grid.arrange(p1, p2, ncol = 2)

    # --- Summary Plots2 [] ---
    # Key functions: plotEventRate, plotBaseProductionRate, grid.arrange, layoutPlot, nreads
    p1 <- plotEventRate(s.typhi.rep1)
    p2 <- plotBaseProductionRate(s.typhi.rep1)
    grid.arrange(p1, p2, ncol = 2)
    p1 <- layoutPlot(s.typhi.rep1, attribute = "nreads")
    p2 <- layoutPlot(s.typhi.rep1, attribute = "kb")
    grid.arrange(p1, p2, ncol = 2)

    # --- Heatmap Example [] ---
    # Key functions: baseCalled, filter, left_join, readInfo, group_by, summarise, channelHeatmap, grid.arrange
    library(dplyr)

    read_count_2D <- baseCalled(s.typhi.rep1) %>% ## start with base called reads
      filter(strand == 'template') %>% ## keep template so we don't count things twice
      left_join(readInfo(s.typhi.rep1), by = 'id') %>% ## channel stored in @readInfo slot, match by id column
      group_by(channel) %>% ## group according to channel
      summarise(d2_count = length(which(full_2D == TRUE)), ## count those with full 2D status
                d2_prop = length(which(full_2D == TRUE)) / n()) ## divide by total count of reads from channel

    ## plot side-by-side
    data(s.typhi.rep3, package = 'minionSummaryData')
    ## we will plot the median event signal for each read on z-axis
    z_scale = select(eventData(s.typhi.rep3), id, median_signal)
    channelActivityPlot( s.typhi.rep3, zScale = z_scale )

    # --- Pentamer Correlation [] ---
    # Key functions: plotKmerFrequencyCorrelation, writeFastq, fastq, tempfile
    plotKmerFrequencyCorrelation( s.typhi.rep3, only2D = FALSE )
    library(ShortRead)
    writeFastq( fastq( s.typhi.rep1 ), file = tempfile() )

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
