#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cn.farms
// This package implements the cn.FARMS algorithm for copy number variation (CNV) analysis. cn.FARMS al
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cn.farms/inst/doc/cn.farms.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cn.farms")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CN_FARMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cn_farms"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cn.farms:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cn.farms:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cn_farms_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cn_farms_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cn_farms_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cn.farms)
    library(jsonlite)

    # --- Single-locus Summarization [] ---
    # Key functions: slSummarization, assayData
    summaryParam <- list(cyc = 10)
    callParam <- list(cores = 1, runtype = "ff")
    slData <- slSummarization(
        normData, 
        summaryMethod = "Variational", 
        summaryParam = summaryParam,
        callParam = callParam,
        summaryWindow = "std"
    )
    sl_intensity <- assayData(slData)$intensity[1:6, 1:5]
    sl_lz <- assayData(slData)$L_z[1:6, 1:5]


    # --- Data Combination [] ---
    # Key functions: combineData
    combData <- combineData(slData, npData, runtype = "ff")


    # --- Multi-locus Summarization [] ---
    # Key functions: mlSummarization, assayData
    windowParam <- list(windowSize = 5, overlap = TRUE)
    summaryParam <- list(cyc = 20)
    callParam <- list(cores = 1, runtype = "ff")
    mlData <- mlSummarization(
        slData, 
        windowMethod = "std", 
        windowParam = windowParam, 
        summaryMethod = "Variational", 
        summaryParam = summaryParam, 
        callParam = callParam
    )
    ml_intensity <- assayData(mlData)$intensity[1:6, 1:5]


    # --- Copy Number Segmentation [] ---
    # Key functions: dnaCopySf, fData
    colnames(assayData(mlData)$L_z) <- sampleNames(mlData)
    segments <- dnaCopySf(
        x = assayData(mlData)$L_z[, 1:10], 
        chrom = fData(mlData)$chrom, 
        maploc = fData(mlData)$start, 
        cores = 1, 
        smoothing = FALSE
    )
    seg_info <- fData(segments)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cn_farms_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cn_farms_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cn_farms_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CN_FARMS:", paste0("    cn_farms: ", packageVersion("cn.farms"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cn_farms_results.csv
    touch ${prefix}_cn_farms_output.rds
    echo "BIOC_CN_FARMS:" > versions.yml
    echo "    cn_farms: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CN_FARMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CN_FARMS(ch_input)

    emit:
    results  = BIOC_CN_FARMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CN_FARMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CN_FARMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CN_FARMS.out.versions  // channel: path(versions.yml)
}
