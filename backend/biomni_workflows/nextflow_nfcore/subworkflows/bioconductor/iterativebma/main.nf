#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iterativeBMA
// The iterative Bayesian Model Averaging (BMA) algorithm is a variable selection and classification al
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iterativeBMA/inst/doc/iterativeBMA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iterativeBMA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ITERATIVEBMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iterativebma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iterativebma:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iterativebma:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iterativebma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iterativebma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iterativebma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iterativeBMA)
    library(jsonlite)

    # --- Trainingstep [] ---
    # Key functions: train
    ## training phase: select relevant genes
    ret.bic.glm <- iterateBMAglm.train (train.expr.set=trainData, trainClass, p=100)
    ret.bic.glm$namesx
    ret.bic.glm$probne0
    ## get the selected genes with probne0 > 0
    # --- Teststep [] ---
    # Key functions: exprs, score
    ## The test ExpressionSet is called testData.
    data (testData)
    ## get the subset of test data with the genes from the last iteration of bic.glm
    curr.test.dat <- t(exprs(testData)[ret.gene.names,])
    ## to compute the predicted probabilities for the test samples
    # --- Trainpredictstep [] ---
    # Key functions: predict, score
    ## train and predict
    ret.vec <- iterateBMAglm.train.predict (train.expr.set=trainData, test.expr.set=testData, trainClass, p=100)
    ## compute the Brier Score
    data (testClass)
    brier.score (ret.vec, testClass)
    # --- Trainpredictteststep [] ---
    # Key functions: test
    iterateBMAglm.train.predict.test (train.expr.set=trainData, test.expr.set=testData, trainClass, testClass, p=100)
    # --- Imageplot [] ---
    # Key functions: bma
    imageplot.iterate.bma (ret.bic.glm)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iterativebma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iterativebma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iterativebma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ITERATIVEBMA:", paste0("    iterativebma: ", packageVersion("iterativeBMA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iterativebma_results.csv
    touch ${prefix}_iterativebma_output.rds
    echo "BIOC_ITERATIVEBMA:" > versions.yml
    echo "    iterativebma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ITERATIVEBMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ITERATIVEBMA(ch_input)

    emit:
    results  = BIOC_ITERATIVEBMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ITERATIVEBMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ITERATIVEBMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ITERATIVEBMA.out.versions  // channel: path(versions.yml)
}
