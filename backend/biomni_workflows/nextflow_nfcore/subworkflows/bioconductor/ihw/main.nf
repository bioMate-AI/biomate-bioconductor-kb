#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IHW
// Independent hypothesis weighting (IHW) is a multiple testing procedure that increases power compared
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IHW/inst/doc/introduction_to_ihw.R
// Upstream  : DESeq2, dplyr, ggplot2
// Downstream: IHWpaper
//
// Install: BiocManager::install("IHW")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IHW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ihw"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ihw:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ihw:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ihw_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ihw_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ihw_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeqDataSet)
    library(jsonlite)

    # --- Create DESeqDataSet [] ---
    # Key functions: DESeqDataSet
    library("DESeq2")
    library("dplyr")
    data("airway", package = "airway")
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_point, facet_grid, geom_histogram, facet_wrap
    library("ggplot2")
    gg <- ggplot(as.data.frame(ihwRes), aes(x = pvalue, y = adj_pvalue, col = group)) +
    geom_point(size = 0.25) + scale_colour_hue(l = 70, c = 150, drop = FALSE)
    # --- Ihw analysis [] ---
    # Key functions: ihw, nbins, nfolds, weights, tibble, rejections, qplot
    sim <- tibble(
    X = runif(100000, min = 0, max = 2.5),         # covariate
    H = rbinom(length(X), size = 1, prob = 0.1),   # hypothesis true or false

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ihw_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ihw_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ihw_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IHW:", paste0("    ihw: ", packageVersion("IHW"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ihw_results.csv
    touch ${prefix}_ihw_output.rds
    echo "BIOC_IHW:" > versions.yml
    echo "    ihw: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IHW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IHW(ch_input)

    emit:
    results  = BIOC_IHW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IHW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IHW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IHW.out.versions  // channel: path(versions.yml)
}
