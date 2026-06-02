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
    library(DEGsExtraction)
    library(DEGsToDiseases)
    library(DEGsToPathways)
    library(jsonlite)

    # --- Prepare Count Files [] ---
    # Key functions: rep, rbind
    suppressMessages(library(KnowSeq))
    dir <- system.file("extdata", package="KnowSeq")
    GSE74251 <- read.csv(paste(dir,"GSE74251.csv",sep = "/"))
    # --- Merge Count Files [] ---
    # Key functions: countsToMatrix
    countsInformation <- countsToMatrix("mergedCountsInfo.csv", extension = "count")
    # --- Download Gene Annotation [] ---
    # Key functions: getGenesAnnotation
    myAnnotation <- getGenesAnnotation(rownames(countsMatrix))
    # --- Calculate Gene Expression [] ---
    # Key functions: calculateGeneExpressionValues

    # --- Plot Expression Boxplot [] ---
    # Key functions: dataPlot

    # --- Remove Batch Effect (ComBat) [] ---
    # Key functions: batchEffectRemoval
    batchGroups <- c(1,1,1,1,2,2,1,2,1,2)
    # --- Remove Batch Effect (SVA) [] ---
    # Key functions: batchEffectRemoval
    expressionMatrixCorrected <- batchEffectRemoval(expressionMatrix, labels, method = "sva")
    # --- Extract Differentially Expressed Genes [] ---
    # Key functions: DEGsExtraction

    # --- Plotting orderded boxplot [] ---
    # Key functions: dataPlot
    dataPlot(DEGsMatrix[1:12,],labels,mode = "orderedBoxplot",toPNG = FALSE,toPDF = FALSE)
    # --- Plotting genes boxplot [] ---
    # Key functions: dataPlot
    dataPlot(DEGsMatrix[1:12,],labels,mode = "genesBoxplot",toPNG = FALSE,toPDF = FALSE)
    # --- Plot DEGs Heatmap [] ---
    # Key functions: dataPlot
    dataPlot(DEGsMatrix[1:12,],labels,mode = "heatmap",toPNG = FALSE,toPDF = FALSE)
    # --- Train Machine Learning Classifiers [] ---
    # Key functions: featureSelection, knn_trn, svm_trn, rf_trn
    DEGsMatrixML <- t(DEGsMatrix)
    mrmrRanking <- featureSelection(DEGsMatrixML,labels,colnames(DEGsMatrixML), mode = "mrmr")
    rfRanking <- featureSelection(DEGsMatrixML,labels,colnames(DEGsMatrixML), mode = "rf")
    # --- Plotting ML acc [] ---
    # Key functions: dataPlot

    # --- Plotting ML sens [] ---
    # Key functions: dataPlot

    # --- Plotting ML spec [] ---
    # Key functions: dataPlot


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
