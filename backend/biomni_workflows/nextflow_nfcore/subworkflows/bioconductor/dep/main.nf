#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEP
// This package provides an integrated analysis workflow for robust and reproducible analysis of mass s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEP/inst/doc/DEP.R
// Upstream  : BiocStyle, SummarizedExperiment, dplyr, ggplot2, purrr
// Downstream: none
//
// Install: BiocManager::install("DEP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dep"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dep:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dep:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dep_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dep_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dep_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEP)
    library(jsonlite)

    # --- Table formatting and display [] ---
    # Key functions: run_app, arrange, make_unique, kable, make_se, make_se_parse, plot_frequency, filter_missval
    LFQ_columns <- grep("LFQ.", colnames(data_unique)) # get LFQ column numbers
    data_se <- make_se(data_unique, LFQ_columns, experimental_design)
    LFQ_columns <- grep("LFQ.", colnames(data_unique)) # get LFQ column numbers

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dep_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dep_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dep_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEP:", paste0("    dep: ", packageVersion("DEP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dep_results.csv
    touch ${prefix}_dep_output.rds
    echo "BIOC_DEP:" > versions.yml
    echo "    dep: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEP(ch_input)

    emit:
    results  = BIOC_DEP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEP.out.versions  // channel: path(versions.yml)
}
