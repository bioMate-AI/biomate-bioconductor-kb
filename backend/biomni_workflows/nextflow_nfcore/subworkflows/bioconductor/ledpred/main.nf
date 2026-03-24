#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LedPred
// This package aims at creating a predictive model of regulatory sequences used to score unknown seque
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LedPred/inst/doc/LedPred.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("LedPred")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEDPRED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ledpred"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ledpred:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ledpred:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ledpred_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ledpred_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ledpred_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LedPred)
    library(jsonlite)

    # --- data [] ---
    # Key functions: data
    library(LedPred)
    data(crm.features)
    # --- Mapfeaturestocrms [] ---
    # Key functions: files, mapFeaturesToCRMs
    dirPath <- system.file("extdata", package="LedPred")
    file.list <-   list.files(dirPath, full.names=TRUE)
    background.freq <- file.list[grep("freq", file.list)]
    positive.regions <-  file.list[grep("positive", file.list)]
    negative.regions <-  file.list[grep("negative", file.list)]
    # --- Mctune [] ---
    # Key functions: mcTune
    #crm.features=crm.feature.list$crm.features
    #cost.vector <- c(1,3,10)
    #gamma.vector <- c(1,3,10)
    #c.g.obj <- mcTune(data = crm.features, ranges = list(cost=cost.vector, gamma=gamma.vector), kernel='linear', file.prefix = "vignette")
    #names(c.g.obj)
    # --- Rankfeatures [] ---
    # Key functions: rankFeatures
    #feature.ranking <- rankFeatures(data=crm.features, cost=cost, gamma=gamma, kernel='linear', file.prefix = "vignette")
    #head(feature.ranking)
    # --- Tunefeaturenb [] ---
    # Key functions: tuneFeatureNb
    #feature.nb.tuner.obj <- tuneFeatureNb(data=crm.features, feature.ranking=feature.ranking, kernel='linear', cost=cost, gamma=gamma, file.prefix = "vignette")
    #names(feature.nb.tuner.obj)
    #feature.nb.tuner.obj$best.feature.nb
    # --- Createmodel [] ---
    # Key functions: createModel
    #feature.nb <- 60
    #model.obj <- createModel(data=crm.features, cost=cost, gamma=gamma, feature.ranking=feature.ranking, feature.nb=feature.nb, file.prefix="vignette")
    #names(model.obj)
    #model.obj$model
    # --- Frame [] ---
    # Key functions: frame
    #feature.weights <- as.data.frame(t(t(model.obj$model$coefs) %*% model.obj$model$SV))
    #head(feature.weights)
    # --- Evaluatemodelperformance [] ---
    # Key functions: evaluateModelPerformance
    #probs.labels.list <- evaluateModelPerformance(data=crm.features, feature.ranking=feature.ranking, feature.nb=feature.nb, cost=cost, gamma=gamma, file.prefix = "vignette")
    # --- Mapfeaturestocrms2 [] ---
    # Key functions: files, mapFeaturesToCRMs
    dirPath <- system.file("extdata", package="LedPred")
    file.list <-   list.files(dirPath, full.names=TRUE)
    background.freqs <- file.list[grep("freq", file.list)]
    positive.bed <-  file.list[grep("prediction_small", file.list)]
    TF.matrices <-  file.list[grep("259_matrices_lightNames", file.list)]
    # --- Scoredata [] ---
    # Key functions: scoreData
    #pred.test <- scoreData(data=prediction.crm.features, model=model.obj, score.file="vignette_prediction.tab")
    #pred.test
    # --- Ledpred [] ---
    # Key functions: LedPred
    crm.features=data(crm.features)
    cost.vector <- c(1,3,10)
    gamma.vector <- c(1,3,10)
    #ledpred.obj=LedPred(data=crm.features, cl=1, ranges = list(cost=cost.vector, gamma=gamma.vector), kernel="linear", file.prefix="vignette2")
    #names(ledpred.obj)
    # --- Mapfeaturestocrms3 [] ---
    # Key functions: files, mapFeaturesToCRMs
    dirPath <- system.file("extdata", package="LedPred")
    file.list <-   list.files(dirPath, full.names=TRUE)
    background.freqs <- file.list[grep("freq", file.list)]
    positive.bed <-  file.list[grep("prediction_small", file.list)]
    TF.matrices <-  file.list[grep("259_matrices_lightNames", file.list)]
    # --- Scoredata2 [] ---
    # Key functions: scoreData
    ## #pred.test2 <- scoreData(data=prediction.crm.features2, model=ledpred.list$model.obj, score.file="vignette2_prediction.tab")
    ## #pred.test2

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ledpred_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ledpred_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ledpred_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LEDPRED:", paste0("    ledpred: ", packageVersion("LedPred"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ledpred_results.csv
    touch ${prefix}_ledpred_output.rds
    echo "BIOC_LEDPRED:" > versions.yml
    echo "    ledpred: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LEDPRED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LEDPRED(ch_input)

    emit:
    results  = BIOC_LEDPRED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LEDPRED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LEDPRED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LEDPRED.out.versions  // channel: path(versions.yml)
}
