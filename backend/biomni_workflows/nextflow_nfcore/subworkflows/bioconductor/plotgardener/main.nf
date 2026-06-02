#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plotgardener
// Coordinate-based genomic visualization package for R. It grants users the ability to programmaticall
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plotgardener/inst/doc/introduction_to_plotgardener.R
// Upstream  : plotgardenerData
// Downstream: none
//
// Install: BiocManager::install("plotgardener")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLOTGARDENER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plotgardener"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plotgardener:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plotgardener:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plotgardener_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plotgardener_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plotgardener_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(plotgardener)
    library(jsonlite)

    # --- Genomic Signal Visualization [] ---
    # Key functions: plotSignal, plotGenes
    library(plotgardenerData)
    data("IMR90_ChIP_H3K27ac_signal")
    plotSignal(
        data = IMR90_ChIP_H3K27ac_signal,
        chrom = "chr21", chromstart = 28000000, chromend = 30300000,
        assembly = "hg19"
    )
    plotGenes(
        assembly = "hg19",
        chrom = "chr21", chromstart = 28000000, chromend = 30300000
    )


    # --- Hi-C Interaction Plotting [] ---
    # Key functions: plotHicSquare, annoHeatmapLegend, annoGenomeLabel
    library(plotgardenerData)
    data("IMR90_HiC_10kb")
    hicPlot <- plotHicSquare(
        data = IMR90_HiC_10kb,
        chrom = "chr21", chromstart = 28000000, chromend = 30300000,
        assembly = "hg19",
        x = 0.25, y = 0.25, width = 2.5, height = 2.5,
        default.units = "inches"
    )
    annoHeatmapLegend(
        plot = hicPlot,
        x = 2.85, y = 0.25, width = 0.1, height = 1.25,
        default.units = "inches"
    )
    annoGenomeLabel(
        plot = hicPlot,
        x = 0.25, y = 2.75, width = 2.5, height = 0.25,
        default.units = "inches"
    )


    # --- Association Mapping Visualization [] ---
    # Key functions: plotManhattan
    library(plotgardenerData)
    data("hg19_insulin_GWAS")
    plotManhattan(
        data = hg19_insulin_GWAS,
        assembly = "hg19",
        fill = c("steel blue", "grey"),
        ymax = 1.1, cex = 0.20
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plotgardener_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plotgardener_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plotgardener_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLOTGARDENER:", paste0("    plotgardener: ", packageVersion("plotgardener"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plotgardener_results.csv
    touch ${prefix}_plotgardener_output.rds
    echo "BIOC_PLOTGARDENER:" > versions.yml
    echo "    plotgardener: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLOTGARDENER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLOTGARDENER(ch_input)

    emit:
    results  = BIOC_PLOTGARDENER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLOTGARDENER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLOTGARDENER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLOTGARDENER.out.versions  // channel: path(versions.yml)
}
