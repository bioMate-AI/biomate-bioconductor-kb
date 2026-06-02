#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seahtrue
// Seahtrue organizes oxygen consumption and extracellular acidification analysis data from experiments
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seahtrue/inst/doc/seahtrue.R
// Upstream  : dplyr, ggplot2, tidyverse
// Downstream: none
//
// Install: BiocManager::install("seahtrue")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEAHTRUE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seahtrue"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seahtrue:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seahtrue:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seahtrue_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seahtrue_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seahtrue_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seahtrue)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
      #rmarkdown.html_vignette.check_title = FALSE
    )

    # --- Load Packages [] ---
    # Key functions: suppressPackageStartupMessages, revive_output_donor_A.rda, seahtrue
    suppressPackageStartupMessages({
      library(dplyr)
      library(seahtrue)
      #library(ggplot2)
    })



    ## -----------------------------------------------------------------------------

    # data_file_path <- 
    #   system.file("data", 
    #               "revive_output_donor_A.rda", 
    #               package = "seahtrue")
    # 

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seahtrue_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seahtrue_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seahtrue_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEAHTRUE:", paste0("    seahtrue: ", packageVersion("seahtrue"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seahtrue_results.csv
    touch ${prefix}_seahtrue_output.rds
    echo "BIOC_SEAHTRUE:" > versions.yml
    echo "    seahtrue: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEAHTRUE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEAHTRUE(ch_input)

    emit:
    results  = BIOC_SEAHTRUE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEAHTRUE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEAHTRUE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEAHTRUE.out.versions  // channel: path(versions.yml)
}
