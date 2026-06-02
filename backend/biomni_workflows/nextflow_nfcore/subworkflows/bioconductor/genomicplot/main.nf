#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicPlot
// Visualization of next generation sequencing (NGS) data is essential for interpreting high-throughput
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicPlot/inst/doc/GenomicPlot_vignettes.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GenomicPlot")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICPLOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicplot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicplot:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicplot:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicplot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicplot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicplot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicPlot)
    library(jsonlite)

    # --- Metagene Plotting [] ---
    # Key functions: plot_5parts_metagene
    plot_5parts_metagene(
        queryFiles = queryfiles,
        gFeatures_list = list("metagene" = gf5_meta),
        inputFiles = inputfiles,
        scale = FALSE,
        verbose = FALSE,
        transform = NA,
        smooth = TRUE,
        stranded = TRUE,
        outPrefix = "metagene_plot",
        importParams = bamimportParams,
        heatmap = TRUE,
        rmOutlier = 0,
        nc = 2
    )


    # --- Region Plotting [] ---
    # Key functions: plot_region
    plot_region(
        queryFiles = queryfiles,
        centerFiles = centerfiles,
        inputFiles = inputfiles,
        nbins = 100,
        heatmap = TRUE,
        scale = FALSE,
        regionName = "narrowPeak",
        importParams = bamimportParams,
        verbose = FALSE,
        fiveP = -500,
        threeP = 500,
        smooth = TRUE,
        transform = NA,
        stranded = TRUE,
        outPrefix = "region_plot",
        Ylab = "Coverage/base/peak",
        rmOutlier = 0,
        nc = 2
    )


    # --- Peak Annotation [] ---
    # Key functions: plot_peak_annotation
    pa <- plot_peak_annotation(
        peakFile = centerfile,
        gtfFile = gtffile,
        importParams = bamimportParams,
        fiveP = -2000,
        dsTSS = 300,
        threeP = 1000,
        simple = FALSE,
        verbose = FALSE,
        outPrefix = "annotation_plot"
    )


    # --- Correlation and Overlap Analysis [] ---
    # Key functions: plot_bam_correlation, plot_overlap_bed
    plot_bam_correlation(
        bamFiles = bamQueryFiles, binSize = 100000,
        outPrefix = "correlation_plot",
        importParams = bamimportParams, nc = 2, verbose = FALSE
    )
    plot_overlap_bed(
        bedList = queryFiles, importParams = bamimportParams,
        pairOnly = FALSE, stranded = FALSE, outPrefix = "overlap_plot"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicplot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicplot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicplot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICPLOT:", paste0("    genomicplot: ", packageVersion("GenomicPlot"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicplot_results.csv
    touch ${prefix}_genomicplot_output.rds
    echo "BIOC_GENOMICPLOT:" > versions.yml
    echo "    genomicplot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICPLOT(ch_input)

    emit:
    results  = BIOC_GENOMICPLOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICPLOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICPLOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICPLOT.out.versions  // channel: path(versions.yml)
}
