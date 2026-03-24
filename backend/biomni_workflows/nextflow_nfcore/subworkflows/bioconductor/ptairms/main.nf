#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ptairMS
// This package implements a suite of methods to preprocess data from PTR-TOF-MS instruments (HDF5 form
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ptairMS/inst/doc/ptairMS.R
// Upstream  : ptairData
// Downstream: none
//
// Install: BiocManager::install("ptairMS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PTAIRMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ptairms"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ptairms:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ptairms:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ptairms_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ptairms_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ptairms_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ptairMS)
    library(jsonlite)

    # --- Visualization and reporting [] ---
    # Key functions: opls, getLoadingMN
    exhaledPca<-ropls::opls(exhaledEset,crossvalI=5,info.txtC="none",fig.pdfC="none")
    ropls::plot(exhaledPca, parAsColFcVn=Biobase::pData(exhaledEset)[, "individual"],typeVc="x-score")
    load1<-ropls::getLoadingMN(exhaledPca)[,1]
    # --- Table formatting and display [] ---
    # Key functions: createPtrSet, getFileNames, kable, plotCalib, calibration, changeTimeLimits, readRaw, timeLimits
    plotFeatures(exhaledPtrset,mz = 53.0387,typePlot = "ggplot",colorBy = "individual")
    plotFeatures(exhaledPtrset,mz = 67.0539,typePlot = "ggplot",colorBy = "individual")
    dir <- system.file("extdata/mycobacteria",  package = "ptairData")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ptairms_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ptairms_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ptairms_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PTAIRMS:", paste0("    ptairms: ", packageVersion("ptairMS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ptairms_results.csv
    touch ${prefix}_ptairms_output.rds
    echo "BIOC_PTAIRMS:" > versions.yml
    echo "    ptairms: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PTAIRMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PTAIRMS(ch_input)

    emit:
    results  = BIOC_PTAIRMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PTAIRMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PTAIRMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PTAIRMS.out.versions  // channel: path(versions.yml)
}
