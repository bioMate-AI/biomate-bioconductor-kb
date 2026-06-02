#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rScudo
// SCUDO (Signature-based Clustering for Diagnostic Purposes) is a rank-based method for the analysis o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rScudo/inst/doc/rScudo-vignette.R
// Upstream  : ALL
// Downstream: none
//
// Install: BiocManager::install("rScudo")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSCUDO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rscudo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rscudo:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rscudo:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rscudo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rscudo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rscudo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rScudo)
    library(jsonlite)

    # --- Network Construction and Plotting [] ---
    # Key functions: scudoTrain, scudoNetwork, scudoPlot
    data(ALL)
    bt <- as.factor(stringr::str_extract(pData(ALL)$BT, "^."))
    inTrain <- caret::createDataPartition(bt, list = FALSE)
    trainData <- ALL[, inTrain]
    trainRes <- scudoTrain(
        trainData, groups = bt[inTrain],
        nTop = 100, nBottom = 100, alpha = 0.1
    )
    trainNet <- scudoNetwork(trainRes, N = 0.25)
    scudoPlot(trainNet, vertex.label = NA)


    # --- Classification and Validation [] ---
    # Key functions: scudoTrain, scudoTest, scudoClassify
    data(ALL)
    bt <- as.factor(stringr::str_extract(pData(ALL)$BT, "^."))
    inTrain <- caret::createDataPartition(bt, list = FALSE)
    trainData <- ALL[, inTrain]
    testData <- ALL[, -inTrain]
    trainRes <- scudoTrain(
        trainData, groups = bt[inTrain],
        nTop = 100, nBottom = 100, alpha = 0.1
    )
    testRes <- scudoTest(
        trainRes, testData, bt[-inTrain],
        nTop = 100, nBottom = 100
    )
    classRes <- scudoClassify(
        trainData, testData, N = 0.25,
        nTop = 100, nBottom = 100,
        trainGroups = bt[inTrain], alpha = 0.1
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rscudo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rscudo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rscudo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSCUDO:", paste0("    rscudo: ", packageVersion("rScudo"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rscudo_results.csv
    touch ${prefix}_rscudo_output.rds
    echo "BIOC_RSCUDO:" > versions.yml
    echo "    rscudo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSCUDO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSCUDO(ch_input)

    emit:
    results  = BIOC_RSCUDO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSCUDO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSCUDO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSCUDO.out.versions  // channel: path(versions.yml)
}
