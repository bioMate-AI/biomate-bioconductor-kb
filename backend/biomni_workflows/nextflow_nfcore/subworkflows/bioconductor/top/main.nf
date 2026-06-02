#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TOP
// TOP constructs a transferable model across gene expression platforms for prospective experiments. Su
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TOP/inst/doc/BuildingATOPModel.R
// Upstream  : Biobase, BiocStyle, curatedOvarianData, dplyr, ggbeeswarm
// Downstream: none
//
// Install: BiocManager::install("TOP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-top"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-top:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-top:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_top_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_top_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_top_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TOP)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    library(BiocStyle)

    # --- Warning = False [] ---
    # Key functions: suppressPackageStartupMessages, theme_set
    suppressPackageStartupMessages({
      library(tidyverse)
      library(survival)
      library(dplyr)
      library(survminer)
      library(Biobase)
      library(ggsci)
      library(ggbeeswarm)
      library(TOP)
      library(curatedOvarianData)
    })

    theme_set(theme_bw())

    # --- Eval = False [] ---
    # Key functions: requireNamespace, install, GSE12418_eset, curatedOvarianData, GSE30009_eset
    #  # Install the package from Bioconductor
    #  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    #    install.packages("BiocManager")
    #  }
    #  BiocManager::install("TOP")

    ## -----------------------------------------------------------------------------
    data("GSE12418_eset", package = "curatedOvarianData")
    data("GSE30009_eset", package = "curatedOvarianData")

    # --- Japan A [] ---
    # Key functions: GSE32062.GPL6480_eset, GSE9891_eset, GSE32063_eset, TCGA.RNASeqV2_eset, metastasis, E.MTAB.386_eset
    data("GSE32062.GPL6480_eset")
    japan_a <- GSE32062.GPL6480_eset

    data("GSE9891_eset")
    tothill <- GSE9891_eset

    data("GSE32063_eset")
    japan_b <- GSE32063_eset

    data("TCGA.RNASeqV2_eset")
    selection <- TCGA.RNASeqV2_eset$tumorstage %in% c(3, 4) & TCGA.RNASeqV2_eset$site_of_tumor_first_recurrence == "metastasis"
    selection[is.na(selection)] <- FALSE
    tcgarnaseq <- TCGA.RNASeqV2_eset[, selection]

    data("E.MTAB.386_eset")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_top_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_top_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_top_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TOP:", paste0("    top: ", packageVersion("TOP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_top_results.csv
    touch ${prefix}_top_output.rds
    echo "BIOC_TOP:" > versions.yml
    echo "    top: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TOP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TOP(ch_input)

    emit:
    results  = BIOC_TOP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TOP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TOP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TOP.out.versions  // channel: path(versions.yml)
}
