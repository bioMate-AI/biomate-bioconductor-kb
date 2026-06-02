#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: countsimQC
// countsimQC provides functionality to create a comprehensive report comparing a broad range of charac
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/countsimQC/inst/doc/countsimQC.R
// Upstream  : DESeq2
// Downstream: none
//
// Install: BiocManager::install("countsimQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COUNTSIMQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-countsimqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-countsimqc:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-countsimqc:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_countsimqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_countsimqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_countsimqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(countsimQC)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(echo = TRUE,
                          crop = NA)

    # --- Warning = False [] ---
    # Key functions: suppressPackageStartupMessages, function
    suppressPackageStartupMessages({
      library(countsimQC)
      library(DESeq2)
    })

    data(countsimExample)
    countsimExample
    countsimExample <- lapply(countsimExample, function(cse) {
      cse[seq_len(1500), ]
    })

    # --- Results = "hide" [] ---
    # Key functions: tempdir, countsimQCReport, countsim_report.html, html_document
    tempDir <- tempdir()
    countsimQCReport(ddsList = countsimExample, outputFile = "countsim_report.html",
                     outputDir = tempDir, outputFormat = "html_document", 
                     showCode = FALSE, forceOverwrite = TRUE,
                     savePlots = TRUE, description = "This is my test report.", 
                     maxNForCorr = 25, maxNForDisp = Inf, 
                     calculateStatistics = TRUE, subsampleSize = 25,
                     kfrac = 0.01, kmin = 5, 
                     permutationPvalues = FALSE, nPermutations = NULL)

    # --- Warning = False [] ---
    # Key functions: readRDS, dir.exists, dir.create, generateIndividualPlots, countsim_report_ggplots.rds, figures
    ggplots <- readRDS(file.path(tempDir, "countsim_report_ggplots.rds"))
    if (!dir.exists(file.path(tempDir, "figures"))) {
      dir.create(file.path(tempDir, "figures"))
    }
    generateIndividualPlots(ggplots, device = "pdf", nDatasets = 3, 
                            outputDir = file.path(tempDir, "figures"))

    ## -----------------------------------------------------------------------------
    data(countsimExample_dfmat)
    names(countsimExample_dfmat)
    lapply(countsimExample_dfmat, class)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_countsimqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_countsimqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_countsimqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COUNTSIMQC:", paste0("    countsimqc: ", packageVersion("countsimQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_countsimqc_results.csv
    touch ${prefix}_countsimqc_output.rds
    echo "BIOC_COUNTSIMQC:" > versions.yml
    echo "    countsimqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COUNTSIMQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COUNTSIMQC(ch_input)

    emit:
    results  = BIOC_COUNTSIMQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COUNTSIMQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COUNTSIMQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COUNTSIMQC.out.versions  // channel: path(versions.yml)
}
