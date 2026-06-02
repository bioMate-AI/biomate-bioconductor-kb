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
    library(CrossValParams)
    library(DataFrame)
    library(ModellingParams)
    library(PredictParams)
    library(TrainParams)
    library(jsonlite)

    # --- Crossvalidate [] ---
    # Key functions: crossValidate, performancePlot
    -----------------------------------------------------------------------------------------------------------------------
    result <- crossValidate(measurements, classes, classifier = "SVM",
                            nFolds = 5, nRepeats = 2, nCores = 1)
    performancePlot(result)
    # --- Dataframe [] ---
    # Key functions: DataFrame, mcols, frame, crossValidate, performancePlot
    -----------------------------------------------------------------------------------------------------------------------
    measurementsDF <- DataFrame(measurements)
    # --- List [] ---
    # Key functions: frame, crossValidate, performancePlot
    -----------------------------------------------------------------------------------------------------------------------
    # Assigns first 10 variables to dataset_1, and the rest to dataset_2
    # --- Modellingparams [] ---
    # Key functions: ModellingParams
    -----------------------------------------------------------------------------------------------------------------------
    ModellingParams()
    # --- Calccvperformance [] ---
    # Key functions: calcCVperformance, performance
    -----------------------------------------------------------------------------------------------------------------------
    DMresults <- calcCVperformance(DMresults)
    DMresults
    performance(DMresults)
    # --- Performanceplot [] ---
    # Key functions: performancePlot
    -----------------------------------------------------------------------------------------------------------------------
    performancePlot(resultsList)
    # --- Rankingplot [] ---
    # Key functions: rankingPlot
    -----------------------------------------------------------------------------------------------------------------------
    rankingPlot(DDresults, topRanked = 1:100, xLabelPositions = c(1, seq(10, 100, 10)))
    # --- List [] ---
    # Key functions: CrossValParams, ModellingParams, TrainParams, PredictParams, runTests
    -----------------------------------------------------------------------------------------------------------------------
    tuneList <- list(cost = c(0.01, 0.1, 1, 10))
    crossValParams <- CrossValParams(permutations = 5, tuneMode = "Resubstitution")
    SVMparams <- ModellingParams(trainParams = TrainParams("SVM", kernel = "linear", tuneParams = tuneList),
                                 predictParams = PredictParams("SVM"))

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
