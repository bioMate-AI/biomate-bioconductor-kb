#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iterativeBMAsurv
// The iterative Bayesian Model Averaging (BMA) algorithm for survival analysis is a variable selection
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iterativeBMAsurv/inst/doc/iterativeBMAsurv.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iterativeBMAsurv")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ITERATIVEBMASURV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iterativebmasurv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iterativebmasurv:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iterativebmasurv:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iterativebmasurv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iterativebmasurv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iterativebmasurv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Surv)
    library(jsonlite)

    # --- Gettraindata [] ---
    # Key functions: data
    ## Use the sample training data. The data matrix is called trainData.
    data(trainData)
    ## The survival time vector for the training set is called trainSurv, where survival times are reported in years.
    data(trainSurv)
    ## The censor vector for the training set is called trainCens, where 0 = censored and 1 = uncensored.
    # --- Trainingstep [] ---
    # Key functions: wrapper
    ## Training phase: select relevant genes
    ## In this example training set, the top 100 genes have already been sorted in decreasing order of their log likelihood
    ret.list <- iterateBMAsurv.train.wrapper (x=trainData, surv.time=trainSurv, cens.vec=trainCens, nbest=5)
    ## Extract the {\tt bic.surv} object
    ret.bic.surv <- ret.list$obj
    # --- Teststep [] ---
    # Key functions: predictiveAssessCategory, Surv, survdiff, unlist
    ## The test data matrix is called testData.
    data(testData)
    ## The survival time vector for the test set is called testSurv, where survival times are reported in years
    data(testSurv)
    ## The censor vector for the test set is called testCens, where 0 = censored and 1 = uncensored
    # --- Trainpredictteststep [] ---
    # Key functions: assess
    ## Use p=10 genes and nbest=5 for fast computation
    ret.bma <- iterateBMAsurv.train.predict.assess (train.dat=trainData, test.dat=testData, surv.time.train=trainSurv, surv.time.test=testSurv, cens.vec.train=trainCens, cens.vec.test=testCens, p=10, nbest=5)
    ## Extract the statistics from this survival analysis run
    number.genes <- ret.bma$nvar
    number.models <- ret.bma$nmodel
    # --- Crossvalidationstep [] ---
    # Key functions: crossVal
    ## Perform 1 run of 2-fold cross validation on the training set, using p=10 genes and nbest=5 for fast computation
    ## Argument {\tt diseaseType} specifies the type of disease present the training samples, used for writing to file
    cv <- crossVal (exset=trainData, survTime=trainSurv, censor=trainCens, diseaseType="DLBCL", noRuns=1, noFolds=2, p=10, nbest=5)
    # --- Imageplot [] ---
    # Key functions: surv
    imageplot.iterate.bma.surv (ret.bic.surv)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iterativebmasurv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iterativebmasurv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iterativebmasurv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ITERATIVEBMASURV:", paste0("    iterativebmasurv: ", packageVersion("iterativeBMAsurv"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iterativebmasurv_results.csv
    touch ${prefix}_iterativebmasurv_output.rds
    echo "BIOC_ITERATIVEBMASURV:" > versions.yml
    echo "    iterativebmasurv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ITERATIVEBMASURV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ITERATIVEBMASURV(ch_input)

    emit:
    results  = BIOC_ITERATIVEBMASURV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ITERATIVEBMASURV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ITERATIVEBMASURV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ITERATIVEBMASURV.out.versions  // channel: path(versions.yml)
}
