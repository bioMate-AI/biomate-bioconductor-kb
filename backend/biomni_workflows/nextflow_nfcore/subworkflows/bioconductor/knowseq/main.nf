#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: KnowSeq
// KnowSeq proposes a novel methodology that comprises the most relevant steps in the Transcriptomic ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/KnowSeq/inst/doc/KnowSeq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("KnowSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-knowseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-knowseq:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-knowseq:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_knowseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_knowseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_knowseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KnowSeq)
    library(DEGsExtraction)
    library(DEGsToDiseases)
    library(DEGsToPathways)
    library(jsonlite)

    # --- Data Preparation and Merging [Data Preparation] ---
    # Key functions: countsToMatrix
    countsInformation <- countsToMatrix(
        "mergedCountsInfo.csv",
        extension = "count"
    )
    countsMatrix <- countsInformation$countsMatrix
    labels <- countsInformation$labels

    # --- Gene Annotation and Expression Calculation [Gene Annotation] ---
    # Key functions: getGenesAnnotation, calculateGeneExpressionValues
    myAnnotation <- getGenesAnnotation(rownames(countsMatrix))
    expressionMatrix <- calculateGeneExpressionValues(
        countsMatrix,
        myAnnotation,
        genesNames = TRUE
    )

    # --- Batch Effect Removal [Batch Correction] ---
    # Key functions: batchEffectRemoval
    expressionMatrixCorrected <- batchEffectRemoval(
        expressionMatrix,
        labels,
        method = "sva"
    )

    # --- Differential Expression Analysis [Differential Expression] ---
    # Key functions: DEGsExtraction, dataPlot
    DEGsInformation <- DEGsExtraction(
        expressionMatrixCorrected,
        labels,
        lfc = 1.0,
        pvalue = 0.01,
        number = 100,
        cov = 1
    )
    DEGsMatrix <- DEGsInformation$DEG_Results$DEGs_Matrix

    # --- Feature Selection and Machine Learning Training [Machine Learning] ---
    # Key functions: featureSelection, knn_trn
    DEGsMatrixML <- t(DEGsMatrix)
    mrmrRanking <- featureSelection(
        DEGsMatrixML,
        labels,
        colnames(DEGsMatrixML),
        mode = "mrmr"
    )
    results_cv_knn <- knn_trn(
        DEGsMatrixML,
        labels,
        names(mrmrRanking)[1:10],
        5
    )

    # --- Machine Learning Testing and Visualization [Model Evaluation] ---
    # Key functions: dataPlot, knn_test
    dataPlot(results_cv_knn, labels, mode = "heatmapResults")
    trainMat <- DEGsMatrixML[c(1:4, 6:9), ]
    trainLab <- labels[c(1:4, 6:9)]
    testMat <- DEGsMatrixML[c(5, 10), ]
    testLab <- labels[c(5, 10)]
    results_test_knn <- knn_test(
        trainMat, trainLab, testMat, testLab,
        names(mrmrRanking)[1:10],
        bestK = results_cv_knn$bestK
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_knowseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_knowseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_knowseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KNOWSEQ:", paste0("    knowseq: ", packageVersion("KnowSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_knowseq_results.csv
    touch ${prefix}_knowseq_output.rds
    echo "BIOC_KNOWSEQ:" > versions.yml
    echo "    knowseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KNOWSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KNOWSEQ(ch_input)

    emit:
    results  = BIOC_KNOWSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KNOWSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KNOWSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KNOWSEQ.out.versions  // channel: path(versions.yml)
}
