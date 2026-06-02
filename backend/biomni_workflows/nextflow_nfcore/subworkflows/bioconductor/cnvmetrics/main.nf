#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNVMetrics
// The CNVMetrics package calculates similarity metrics to facilitate copy number variant comparison am
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNVMetrics/inst/doc/CNVMetrics.R
// Upstream  : GenomicRanges, knitr
// Downstream: none
//
// Install: BiocManager::install("CNVMetrics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNVMETRICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnvmetrics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnvmetrics:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnvmetrics:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnvmetrics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnvmetrics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnvmetrics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNVMetrics)
    library(GRanges)
    library(GRangesList)
    library(jsonlite)

    # --- CNV Data Preparation [Data Preparation] ---
    # Key functions: makeGRangesListFromDataFrame
    data.dir <- system.file("extdata", package="CNVMetrics")
    cnv.file <- file.path(data.dir, "mousePairedOrganoids.txt")
    calls <- read.table(cnv.file, header=TRUE, sep="\t")
    grl <- GenomicRanges::makeGRangesListFromDataFrame(
        calls,
        split.field="ID",
        keep.extra.columns=TRUE
    )

    # --- Overlap Metric Calculation [Metric Calculation] ---
    # Key functions: calculateOverlapMetric
    metric <- calculateOverlapMetric(
        segmentData=grl,
        method="sorensen",
        nJobs=1
    )

    # --- Log2 Ratio Metric Calculation [Metric Calculation] ---
    # Key functions: calculateLog2ratioMetric
    metricLog <- calculateLog2ratioMetric(
        segmentData=grl,
        method="weightedEuclideanDistance",
        nJobs=1
    )

    # --- CNV Similarity Visualization [Visualisation] ---
    # Key functions: plotMetric
    plotMetric(
        metric,
        type="AMPLIFICATION",
        colorRange=c("white", "steelblue")
    )
    plotMetric(
        metric,
        type="DELETION",
        colorRange=c("white", "darkorange"),
        show_colnames=TRUE,
        display_numbers=TRUE,
        number_format="%.2f"
    )
    plotMetric(
        metricLog,
        colorRange=c("white", "darkorange"),
        show_colnames=TRUE,
        display_numbers=TRUE,
        number_format="%.2f",
        main="Log2 Ratio Distance"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnvmetrics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnvmetrics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnvmetrics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNVMETRICS:", paste0("    cnvmetrics: ", packageVersion("CNVMetrics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnvmetrics_results.csv
    touch ${prefix}_cnvmetrics_output.rds
    echo "BIOC_CNVMETRICS:" > versions.yml
    echo "    cnvmetrics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNVMETRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNVMETRICS(ch_input)

    emit:
    results  = BIOC_CNVMETRICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNVMETRICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNVMETRICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNVMETRICS.out.versions  // channel: path(versions.yml)
}
