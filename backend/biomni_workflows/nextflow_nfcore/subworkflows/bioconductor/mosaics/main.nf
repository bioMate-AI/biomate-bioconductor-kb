#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mosaics
// This package provides functions for fitting MOSAiCS and MOSAiCS-HMM, a statistical framework to anal
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mosaics/inst/doc/mosaics-example.R
// Upstream  : mosaicsExample
// Downstream: none
//
// Install: BiocManager::install("mosaics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSAICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mosaics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mosaics:2.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mosaics:2.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mosaics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mosaics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mosaics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mosaics)
    library(jsonlite)

    # --- Data Loading [] ---
    # Key functions: readBins
    binData <- readBins(
        type = c("chip", "input"),
        fileName = c(
            "wgEncodeSydhTfbsGm12878Stat1StdAlnRep1_chr22_sorted.bam_fragL200_bin200.txt",
            "wgEncodeSydhTfbsGm12878InputStdAlnRep1_chr22_sorted.bam_fragL200_bin200.txt"
        )
    )


    # --- Model Fitting [] ---
    # Key functions: mosaicsFit
    fitHM <- mosaicsFit(
        binData,
        analysisType = "IO",
        bgEst = "automatic"
    )


    # --- HMM Model Fitting [] ---
    # Key functions: mosaicsFitHMM
    hmmHM <- mosaicsFitHMM(
        fitHM,
        signalModel = "2S",
        init = "mosaics",
        init.FDR = 0.05,
        parallel = FALSE,
        nCore = 1
    )


    # --- Peak Calling [] ---
    # Key functions: mosaicsPeakHMM
    peakHM <- mosaicsPeakHMM(
        hmmHM,
        FDR = 0.05,
        decoding = "posterior",
        thres = 10,
        parallel = FALSE,
        nCore = 1
    )


    # --- Exporting Results [] ---
    # Key functions: export
    export(
        peakHM,
        type = "txt",
        filename = "peaks_mosaics.txt"
    )
    export(
        peakHM,
        type = "gff",
        filename = "peaks_mosaics.gff"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mosaics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mosaics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mosaics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOSAICS:", paste0("    mosaics: ", packageVersion("mosaics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosaics_results.csv
    touch ${prefix}_mosaics_output.rds
    echo "BIOC_MOSAICS:" > versions.yml
    echo "    mosaics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOSAICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOSAICS(ch_input)

    emit:
    results  = BIOC_MOSAICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOSAICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOSAICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOSAICS.out.versions  // channel: path(versions.yml)
}
