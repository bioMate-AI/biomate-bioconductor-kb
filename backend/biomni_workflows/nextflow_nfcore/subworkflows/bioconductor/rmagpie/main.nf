#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rmagpie
// Microarray Classification is designed for both biologists and statisticians. It offers the ability t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rmagpie/inst/doc/Magpie_examples.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("Rmagpie")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMAGPIE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rmagpie"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rmagpie:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rmagpie:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rmagpie_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rmagpie_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rmagpie_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Average)
    library(jsonlite)

    # --- Load Dataset [] ---
    # Key functions: data
    data('vV70genesDataset')
    # --- One Layer Cross Validation [] ---
    # Key functions: runOneLayerExtCV
    # Necessary to find the same results
    set.seed(234)
    myAssessment <- runOneLayerExtCV(myAssessment)
    myAssessment
    # --- Two Layer Cross Validation [] ---
    # Key functions: runTwoLayerExtCV
    myAssessment <- runTwoLayerExtCV(myAssessment)
    myAssessment
    # --- Classify Observations [] ---
    # Key functions: findFinalClassifier
    myAssessment <- findFinalClassifier(myAssessment)
    # --- Classify New Samples One [] ---
    # Key functions: classifyNewSamples
    newSamplesFile <- system.file(package="Rmagpie","extdata", "vV_newSamples.txt")
    res <- classifyNewSamples( myAssessment,newSamplesFile)
    # --- Classify New Samples Two [] ---
    # Key functions: classifyNewSamples
    newSamplesFile <- system.file(package="Rmagpie","extdata", "vV_newSamples.txt")
    res <- classifyNewSamples( myAssessment,newSamplesFile,optionValue=1)
    # --- Example One [] ---
    # Key functions: getResults
    # All the information on error rates for the repeated one-layer CV
    getResults(myAssessment, 1, topic='errorRate')
    # Cross-validated error rates for the repeated one-layer CV: Une value
    # per size of subset
    getResults(myAssessment, 1, topic='errorRate', errorType='cv')
    # --- Example 2 [] ---
    # Key functions: getResults
    # Frequency of the genes selected among the folds and repeats
    # of the one-layer CV
    res <- getResults(myAssessment, c(1,1), topic='genesSelected', genesType='frequ')
    # Genes selected for the 3rd size of subset in the 2nd fold of the
    # second repeat of one-layer external CV
    # --- Example 3 [] ---
    # Key functions: getResults, Average
    # Best number of genes in one-layer CV
    getResults(myAssessment, 1, topic='bestOptionValue')
    # Best number of genes in the third repeat of one-layer CV
    getResults(myAssessment, c(1,3), topic='bestOptionValue')
    # Average (over the folds), best number of genes in the two-layer CV
    # --- Example 4 [] ---
    # Key functions: getResults
    # Execution time to compute the repeated one-layer CV
    getResults(myAssessment, 1, topic='executionTime')
    # Execution time to compute the third repeat of the repeated one-layer CV
    getResults(myAssessment, c(1,3), topic='executionTime')
    # Execution time to compute the repeated two-layer CV
    # --- Ploterrorsummary1 [] ---
    # Key functions: plotErrorsSummaryOneLayerCV, off
    png("plotErrorsSummaryOneLayerCV.png")
    plotErrorsSummaryOneLayerCV(myAssessment)
    dev.off()
    # --- Ploterrorsummaryrepeated [] ---
    # Key functions: plotErrorsRepeatedOneLayerCV, off
    png("plotSummaryErrorRate.png")
    plotErrorsRepeatedOneLayerCV(myAssessment)
    dev.off()
    # --- Two Layer Cross Validation [] ---
    # Key functions: plotErrorsFoldTwoLayerCV, off
    png("twoLayerCrossValidation.png")
    plotErrorsFoldTwoLayerCV(myAssessment)
    dev.off()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rmagpie_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rmagpie_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rmagpie_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RMAGPIE:", paste0("    rmagpie: ", packageVersion("Rmagpie"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rmagpie_results.csv
    touch ${prefix}_rmagpie_output.rds
    echo "BIOC_RMAGPIE:" > versions.yml
    echo "    rmagpie: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RMAGPIE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RMAGPIE(ch_input)

    emit:
    results  = BIOC_RMAGPIE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RMAGPIE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RMAGPIE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RMAGPIE.out.versions  // channel: path(versions.yml)
}
