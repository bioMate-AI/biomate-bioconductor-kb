#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClassifyR
// The software formalises a framework for classification and survival model evaluation in R. There are
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClassifyR/inst/doc/ClassifyR.R
// Upstream  : grid
// Downstream: none
//
// Install: BiocManager::install("ClassifyR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLASSIFYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-classifyr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-classifyr:3.10.10--r44_0' :
        'quay.io/biocontainers/bioconductor-classifyr:3.10.10--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_classifyr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_classifyr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_classifyr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ClassifyR)
    library(CrossValParams)
    library(DataFrame)
    library(ModellingParams)
    library(PredictParams)
    library(TrainParams)
    library(jsonlite)

    # --- Multi-view Cross-Validation [] ---
    # Key functions: crossValidate, performancePlot
    data(asthma)
    measurementsList <- list(
        assay_1 = as.data.frame(measurements)[, 1:10],
        assay_2 = as.data.frame(measurements)[, 11:2000]
    )
    result_mv <- crossValidate(
        measurementsList,
        classes,
        classifier = "SVM",
        nFolds = 5,
        nRepeats = 3,
        multiViewMethod = "merge"
    )
    mv_plot <- performancePlot(
        result_mv,
        characteristicsList = list(x = "Assay Name")
    )


    # --- Custom Modelling and Testing [] ---
    # Key functions: CrossValParams, ModellingParams, SelectParams, TrainParams, runTests
    data(asthma)
    crossValParams <- CrossValParams(permutations = 5)
    modellingParamsDD <- ModellingParams(
        selectParams = SelectParams("KL"),
        trainParams = TrainParams("naiveBayes"),
        predictParams = NULL
    )
    DDresults <- runTests(
        measurements,
        classes,
        crossValParams,
        modellingParamsDD,
        verbose = 1
    )


    # --- Feature Selection Analysis [] ---
    # Key functions: CrossValParams, runTests, distribution, plotFeatureClasses
    data(asthma)
    crossValParams <- CrossValParams(permutations = 5)
    DMresults <- runTests(measurements, classes, crossValParams, verbose = 1)
    selectionPercentages <- distribution(DMresults, plot = FALSE)
    sortedPercentages <- head(
        selectionPercentages[order(selectionPercentages, decreasing = TRUE)]
    )
    bestGenePlot <- plotFeatureClasses(
        measurements,
        classes,
        names(sortedPercentages)[1],
        dotBinWidth = 0.1,
        xAxisLabel = "Normalised Expression"
    )


    # --- Performance Comparison [] ---
    # Key functions: calcCVperformance, samplesMetricMap, performancePlot, ROCplot
    data(asthma)
    cv_params <- CrossValParams(permutations = 2)
    DMresults <- runTests(measurements, classes, cv_params, verbose = 0)
    DDresults <- runTests(measurements, classes, cv_params, verbose = 0)
    DMresults <- calcCVperformance(DMresults)
    DDresults <- calcCVperformance(DDresults)
    resultsList <- list(Abundance = DMresults, Distribution = DDresults)
    metric_map <- samplesMetricMap(resultsList, showXtickLabels = FALSE)
    perf_comparison <- performancePlot(resultsList)
    roc_comparison <- ROCplot(resultsList)


    # --- Parameter Tuning [] ---
    # Key functions: CrossValParams, ModellingParams, TrainParams, PredictParams, runTests
    data(asthma)
    tuneList <- list(cost = c(0.01, 0.1, 1, 10))
    crossValParams <- CrossValParams(
        permutations = 2,
        tuneMode = "Resubstitution"
    )
    SVMparams <- ModellingParams(
        trainParams = TrainParams(
            "SVM",
            kernel = "linear",
            tuneParams = tuneList
        ),
        predictParams = PredictParams("SVM")
    )
    SVMresults <- runTests(
        measurements,
        classes,
        crossValParams,
        SVMparams
    )
    tuned_params <- tunedParameters(SVMresults)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_classifyr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_classifyr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_classifyr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLASSIFYR:", paste0("    classifyr: ", packageVersion("ClassifyR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_classifyr_results.csv
    touch ${prefix}_classifyr_output.rds
    echo "BIOC_CLASSIFYR:" > versions.yml
    echo "    classifyr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLASSIFYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLASSIFYR(ch_input)

    emit:
    results  = BIOC_CLASSIFYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLASSIFYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLASSIFYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLASSIFYR.out.versions  // channel: path(versions.yml)
}
