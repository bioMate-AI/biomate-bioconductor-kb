#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cfDNAPro
// cfDNA fragments carry important features for building cancer sample classification ML models, such a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cfDNAPro/inst/doc/cfDNAPro.R
// Upstream  : scales, ggpubr, ggplot2, dplyr
// Downstream: none
//
// Install: BiocManager::install("cfDNAPro")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFDNAPRO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cfdnapro"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cfdnapro:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cfdnapro:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cfdnapro_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cfdnapro_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cfdnapro_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cfDNAPro)
    library(jsonlite)

    # --- get path to example data [] ---
    # Key functions: examplePath
    library(cfDNAPro)
    data_path <- examplePath("groups_picard")
    # --- single group plot [] ---
    # Key functions: callSize, plotSingleGroup
    cohort1_plot <- cfDNAPro::callSize(path = data_path) %>%
    dplyr::filter(group == as.character("cohort_1")) %>%
    cfDNAPro::plotSingleGroup()
    # --- fragment size distribution [] ---
    # Key functions: callSize, plotSingleGroup, ggarrange
    library(scales)
    library(ggpubr)
    library(ggplot2)
    # --- Median distribution [] ---
    # Key functions: callMetrics, ylim, theme, scale_y_continuous
    Set an order for those groups (i.e. the levels of factors).
    order <- c("cohort_1", "cohort_2", "cohort_3", "cohort_4")
    compare_grps<-callMetrics(data_path) %>% plotMetrics(order=order)
    # --- Modal size bar chart [] ---
    # Key functions: callMode
    order <- c("cohort_1", "cohort_2", "cohort_3", "cohort_4")
    mode_bin <- callMode(data_path) %>% plotMode(order=order,hline = c(167,111,81))
    suppressWarnings(print(mode_bin))
    # --- modal size stacked bar chart [] ---
    # Key functions: callMode, plotModeSummary
    order <- c("cohort_1", "cohort_2", "cohort_3", "cohort_4")
    callMode(data_path) %>%
    # --- interpeak distance [] ---
    # Key functions: callPeakDistance, plotPeakDistance, labs, theme
    order <- c("cohort_1", "cohort_2", "cohort_4", "cohort_3")
    inter_peak_dist<-callPeakDistance(path = data_path,  limit = c(50, 135)) %>%
    plotPeakDistance(order = order) +
    # --- intervalley distance [] ---
    # Key functions: callValleyDistance, plotValleyDistance, labs, theme
    order <- c("cohort_1", "cohort_2", "cohort_4", "cohort_3")
    inter_valley_dist<-callValleyDistance(path = data_path,
    limit = c(50, 135)) %>%
    # --- example Path [] ---
    # Key functions: examplePath, callPeakDistance, callValleyDistance, callSize, coord_cartesian
    library(ggplot2)
    library(cfDNAPro)
    exam_path <- examplePath("step6")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cfdnapro_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cfdnapro_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cfdnapro_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CFDNAPRO:", paste0("    cfdnapro: ", packageVersion("cfDNAPro"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cfdnapro_results.csv
    touch ${prefix}_cfdnapro_output.rds
    echo "BIOC_CFDNAPRO:" > versions.yml
    echo "    cfdnapro: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CFDNAPRO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CFDNAPRO(ch_input)

    emit:
    results  = BIOC_CFDNAPRO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CFDNAPRO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CFDNAPRO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CFDNAPRO.out.versions  // channel: path(versions.yml)
}
