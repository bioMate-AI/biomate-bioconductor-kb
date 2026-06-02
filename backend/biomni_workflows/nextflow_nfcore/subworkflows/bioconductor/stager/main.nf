#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: stageR
// The stageR package allows automated stage-wise analysis of high-throughput gene expression data. The
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/stageR/inst/doc/stageRVignette.R
// Upstream  : Biobase, DEXSeq, edgeR, limma, utils
// Downstream: rnaseqDTU
//
// Install: BiocManager::install("stageR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STAGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-stager"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-stager:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-stager:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_stager_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_stager_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_stager_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(stageR)
    library(DEXSeqDataSet)
    library(DGEList)
    library(TestResults)
    library(jsonlite)

    # --- Stage-wise Object Creation ---
    # Key functions: stageR
    pScreen <- runif(100)
    names(pScreen) <- paste0("gene", 1:100)
    pConfirmation <- matrix(runif(300), ncol=3)
    dimnames(pConfirmation) <- list(
        paste0("gene", 1:100),
        c("t1", "t2", "t3")
    )
    stageRObj <- stageR(
        pScreen = pScreen,
        pConfirmation = pConfirmation,
        pScreenAdjusted = FALSE
    )

    # --- Stage-wise Adjustment ---
    # Key functions: stageWiseAdjustment
    stageRObj <- stageWiseAdjustment(
        object = stageRObj,
        method = "none",
        alpha = 0.05
    )

    # --- Results Extraction ---
    # Key functions: getAdjustedPValues, getResults
    adjP <- getAdjustedPValues(
        stageRObj,
        onlySignificantGenes = FALSE,
        order = FALSE
    )
    res <- getResults(stageRObj)
    summary_results <- colSums(res)

    # --- Transcript-level Stage-wise Object Creation ---
    # Key functions: stageRTx
    pScreenTx <- runif(50)
    names(pScreenTx) <- paste0("gene", 1:50)
    pConfirmationTx <- matrix(runif(150), ncol=1)
    dimnames(pConfirmationTx) <- list(paste0("tx", 1:150), "transcript")
    tx2gene <- data.frame(
        transcript = paste0("tx", 1:150),
        gene = rep(paste0("gene", 1:50), each=3)
    )
    stageRObjTx <- stageRTx(
        pScreen = pScreenTx,
        pConfirmation = pConfirmationTx,
        pScreenAdjusted = TRUE,
        tx2gene = tx2gene
    )

    # --- Transcript-level Stage-wise Adjustment and Significance ---
    # Key functions: stageWiseAdjustment, getSignificantGenes, getSignificantTx, getAdjustedPValues
    stageRObjTx <- stageWiseAdjustment(
        object = stageRObjTx,
        method = "dtu",
        alpha = 0.05
    )
    sigGenes <- getSignificantGenes(stageRObjTx)
    sigTx <- getSignificantTx(stageRObjTx)
    padjTx <- getAdjustedPValues(
        stageRObjTx,
        order = TRUE,
        onlySignificantGenes = FALSE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_stager_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_stager_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_stager_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STAGER:", paste0("    stager: ", packageVersion("stageR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stager_results.csv
    touch ${prefix}_stager_output.rds
    echo "BIOC_STAGER:" > versions.yml
    echo "    stager: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STAGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STAGER(ch_input)

    emit:
    results  = BIOC_STAGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STAGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STAGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STAGER.out.versions  // channel: path(versions.yml)
}
