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


    # --- Global Code [] ---
    # Key functions: suppressPackageStartupMessages, loadDb, extdata, txdb.sql
    suppressPackageStartupMessages(library(GenomicPlot, quietly = TRUE))

    txdb <- AnnotationDbi::loadDb(system.file("extdata", "txdb.sql", 
                                              package = "GenomicPlot"))

    # --- Metagene Code [] ---
    # Key functions: setImportParams, plot_5parts_metagene, extdata, treat_chr19.bam, clip_bam, input_chr19.bam, clip_input, start
    data(gf5_meta)

    queryfiles <- system.file("extdata", "treat_chr19.bam", 
                              package = "GenomicPlot")
    names(queryfiles) <- "clip_bam"
    inputfiles <- system.file("extdata", "input_chr19.bam", 
                              package = "GenomicPlot")
    names(inputfiles) <- "clip_input"

    # --- Region Code [] ---
    # Key functions: setImportParams, plot_region, extdata, test_chip_peak_chr19.narrowPeak, chip_treat_chr19.bam, chip_bam, chip_input_chr19.bam, chip_input
    centerfiles <- system.file("extdata", "test_chip_peak_chr19.narrowPeak", 
                               package = "GenomicPlot")
    names(centerfiles) <- c("NarrowPeak")
    queryfiles <- c(
      system.file("extdata", "chip_treat_chr19.bam", package = "GenomicPlot")
    )
    names(queryfiles) <- c("chip_bam")
    inputfiles <- c(
      system.file("extdata", "chip_input_chr19.bam", package = "GenomicPlot")
    )

    # --- Locus Code [] ---
    # Key functions: plot_locus, extdata, test_clip_peak_chr19.bed, test_chip_peak_chr19.bed, iCLIPPeak, chip_treat_chr19.bam, chip_bam, chip_input_chr19.bam
    centerfiles <- c(
      system.file("extdata", "test_clip_peak_chr19.bed", package = "GenomicPlot"),
      system.file("extdata", "test_chip_peak_chr19.bed", package = "GenomicPlot")
    )
    names(centerfiles) <- c("iCLIPPeak", "SummitPeak")
    queryfiles <- c(
      system.file("extdata", "chip_treat_chr19.bam", package = "GenomicPlot")
    )
    names(queryfiles) <- c("chip_bam")
    # --- Annotation Code [] ---
    # Key functions: setImportParams, plot_peak_annotation, extdata, gencode.v19.annotation_chr19.gtf, test_chip_peak_chr19.bed, center, hg19
    gtffile <- system.file("extdata", "gencode.v19.annotation_chr19.gtf", 
                           package = "GenomicPlot")

    centerfile <- system.file("extdata", "test_chip_peak_chr19.bed", 
                              package = "GenomicPlot")
    names(centerfile) <- c("SummitPeak")

    # --- Bam Correlation [] ---
    # Key functions: setImportParams, plot_bam_correlation, extdata, chip_input_chr19.bam, chip_treat_chr19.bam, chip_input, chip_treat, start
    bamQueryFiles <- c(
       system.file("extdata", "chip_input_chr19.bam", package = "GenomicPlot"),
       system.file("extdata", "chip_treat_chr19.bam", package = "GenomicPlot")
    )
    names(bamQueryFiles) <- c("chip_input", "chip_treat")


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
