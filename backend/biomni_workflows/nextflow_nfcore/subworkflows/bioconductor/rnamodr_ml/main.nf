#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RNAmodR.ML
// RNAmodR.ML extend the functionality of the RNAmodR package and classical detection strategies toward
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RNAmodR.ML/inst/doc/RNAmodR.ML.R
// Upstream  : GenomicRanges, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("RNAmodR.ML")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNAMODR_ML {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnamodr_ml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnamodr.ml:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnamodr.ml:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnamodr_ml_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnamodr_ml_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnamodr_ml_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNAmodR.ML)
    library(jsonlite)

    # --- Machine Learning Model Integration [] ---
    # Key functions: setMLModel, useModel
    model <- ranger::ranger(labels ~ ., data.frame(trainingData))
    setClass("ModifierMLexample",
             contains = c("ModifierMLranger"),
             prototype = list(model = model))
    mlmodel <- new("ModifierMLexample")
    setMLModel(me) <- mlmodel


    # --- Prediction and Evaluation [] ---
    # Key functions: plotROC, plotDataByCoord, modifications
    me <- aggregate(me, force = TRUE)
    plotROC(me, dmod)
    mod <- modifications(me)
    plotDataByCoord(sequenceData(me), mod[[1]][1])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnamodr_ml_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnamodr_ml_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnamodr_ml_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNAMODR_ML:", paste0("    rnamodr_ml: ", packageVersion("RNAmodR.ML"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnamodr_ml_results.csv
    touch ${prefix}_rnamodr_ml_output.rds
    echo "BIOC_RNAMODR_ML:" > versions.yml
    echo "    rnamodr_ml: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNAMODR_ML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNAMODR_ML(ch_input)

    emit:
    results  = BIOC_RNAMODR_ML.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNAMODR_ML.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNAMODR_ML.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNAMODR_ML.out.versions  // channel: path(versions.yml)
}
