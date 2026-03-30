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

    # --- LoadDb analysis [] ---
    # Key functions: install_github, loadDb, setImportParams, plot_5parts_metagene, plot_region, plot_locus, plot_peak_annotation, plot_bam_correlation
    gtffile <- system.file("extdata", "gencode.v19.annotation_chr19.gtf",
    centerfile <- system.file("extdata", "test_chip_peak_chr19.bed",
    names(centerfile) <- c("SummitPeak")

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
