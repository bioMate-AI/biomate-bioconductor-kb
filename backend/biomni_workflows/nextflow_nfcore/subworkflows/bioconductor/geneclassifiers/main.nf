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

    # --- Querying Classifiers [Querying] ---
    # Key functions: showClassifierList, getClassifier, getWeights, getDecisionBoundaries, getEventChain
    classifiers <- showClassifierList()
    emc92 <- getClassifier("EMC92")
    hm19 <- getClassifier("HM19")
    emc92_weights <- getWeights(emc92)[1:10]
    hm19_boundaries <- getDecisionBoundaries(hm19)
    emc92_events <- getEventChain(emc92)

    # --- Data Normalization [Normalization] ---
    # Key functions: setNormalizationMethod
    data(exampleMAS5, package = "geneClassifiers")
    fixedData <- setNormalizationMethod(
        exampleMAS5,
        method = "MAS5.0",
        targetValue = 500
    )

    # --- Running Classifiers [Classification] ---
    # Key functions: runClassifier
    resultsEMC92 <- runClassifier("EMC92", fixedData)
    resultsUAMS70 <- runClassifier("UAMS70", fixedData)

    # --- Extracting Results [Extraction] ---
    # Key functions: getScores, getClassifications
    results_df <- data.frame(
        "score_EMC92"  = getScores(resultsEMC92),
        "class_EMC92"  = getClassifications(resultsEMC92),
        "score_UAMS70" = getScores(resultsUAMS70),
        "class_UAMS70" = getClassifications(resultsUAMS70)
    )

    # --- Reweighted Classification and Visualization [Visualization] ---
    # Key functions: runClassifier, getScores, getDecisionBoundaries, getClassifier
    resultsEMC92.reWeighted <- runClassifier(
        "EMC92",
        fixedData[1:70, ],
        allow.reweighted = TRUE
    )
    plot(
        x = getScores(resultsEMC92),
        y = getScores(resultsEMC92.reWeighted),
        xlab = "complete",
        ylab = "reweighted",
        main = "EMC92 scores"
    )
    abline(
        v = getDecisionBoundaries(getClassifier(resultsEMC92)),
        h = getDecisionBoundaries(getClassifier(resultsEMC92.reWeighted)),
        col = "red"
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
