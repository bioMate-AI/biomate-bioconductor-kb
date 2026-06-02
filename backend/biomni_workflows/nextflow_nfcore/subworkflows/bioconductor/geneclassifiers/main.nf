#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: geneClassifiers
// This packages aims for easy accessible application of classifiers which have been published in liter
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/geneClassifiers/inst/doc/geneClassifiers.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("geneClassifiers")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENECLASSIFIERS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geneclassifiers"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geneclassifiers:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geneclassifiers:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geneclassifiers_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geneclassifiers_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geneclassifiers_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(geneClassifiers)
    library(jsonlite)

    # --- Showclassifierlist [] ---
    # Key functions: showClassifierList
    showClassifierList()
    # --- Getclassifier [] ---
    # Key functions: getClassifier
    EMC92Classifier<-getClassifier("EMC92")
    EMC92Classifier
    HM19Classifier<-getClassifier("HM19")
    HM19Classifier
    # --- Getweights [] ---
    # Key functions: getWeights
    getWeights(EMC92Classifier)[1:10]
    # --- Getdecisionboundaries [] ---
    # Key functions: getDecisionBoundaries
    getDecisionBoundaries(HM19Classifier)
    # --- Geteventchain [] ---
    # Key functions: getEventChain
    getEventChain(EMC92Classifier)
    # --- Data [] ---
    # Key functions: preproc, experimentData
    library(Biobase)
    data(exampleMAS5)
    class(exampleMAS5) #an object of class ExpressionSet
    dim(exampleMAS5)
    preproc(experimentData(exampleMAS5))
    # --- Setnormalizationmethod [] ---
    # Key functions: setNormalizationMethod
    fixedData <- setNormalizationMethod( exampleMAS5, method="MAS5.0", targetValue = 500 )
    fixedData
    # --- Runclassifier [] ---
    # Key functions: runClassifier
    resultsEMC92  <- runClassifier( "EMC92" , fixedData )
    resultsUAMS70 <- runClassifier( "UAMS70", fixedData )
    resultsEMC92
    resultsUAMS70
    # --- Frame [] ---
    # Key functions: frame, getScores, getClassifications

    # --- Runclassifier [] ---
    # Key functions: runClassifier, getScores, getDecisionBoundaries, getClassifier
    resultsEMC92.reWeighted <- runClassifier(
        "EMC92" ,
        fixedData[1:70,] ,
        allow.reweighted=TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geneclassifiers_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geneclassifiers_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geneclassifiers_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENECLASSIFIERS:", paste0("    geneclassifiers: ", packageVersion("geneClassifiers"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geneclassifiers_results.csv
    touch ${prefix}_geneclassifiers_output.rds
    echo "BIOC_GENECLASSIFIERS:" > versions.yml
    echo "    geneclassifiers: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENECLASSIFIERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENECLASSIFIERS(ch_input)

    emit:
    results  = BIOC_GENECLASSIFIERS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENECLASSIFIERS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENECLASSIFIERS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENECLASSIFIERS.out.versions  // channel: path(versions.yml)
}
