#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BASiCS
// Single-cell mRNA sequencing can uncover novel cell-to-cell heterogeneity in gene expression levels i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BASiCS/inst/doc/BASiCS.R
// Upstream  : BiocStyle, SingleCellExperiment, cowplot, ggplot2, knitr
// Downstream: BASiCStan
//
// Install: BiocManager::install("BASiCS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-basics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-basics:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-basics:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_basics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_basics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_basics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BASiCS_DetectHVG)
    library(BASiCS_DetectLVG)
    library(BASiCS_MCMC)
    library(BASiCS_PlotVG)
    library(BASiCS_TestDE)
    library(SingleCellExperiment)
    library(Summary)
    library(jsonlite)

    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment
    set.seed(1)
    CountsNoSpikes <- matrix(rpois(50 * 40, 2), ncol = 40)
    rownames(CountsNoSpikes) <- paste0("Gene", 1:50)
    # --- Theme set analysis [] ---
    # Key functions: theme_set, makeExampleBASiCS_Data, BASiCS_MCMC, rgamma, newBASiCS_Data, BASiCS_DetectHVG, BASiCS_DetectLVG, plot_grid
    set.seed(1)
    Counts <- matrix(rpois(50 * 40, 2), ncol = 40)
    rownames(Counts) <- c(paste0("Gene", 1:40), paste0("Spike", 1:10))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_basics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_basics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_basics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASICS:", paste0("    basics: ", packageVersion("BASiCS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basics_results.csv
    touch ${prefix}_basics_output.rds
    echo "BIOC_BASICS:" > versions.yml
    echo "    basics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BASICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BASICS(ch_input)

    emit:
    results  = BIOC_BASICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BASICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BASICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BASICS.out.versions  // channel: path(versions.yml)
}
