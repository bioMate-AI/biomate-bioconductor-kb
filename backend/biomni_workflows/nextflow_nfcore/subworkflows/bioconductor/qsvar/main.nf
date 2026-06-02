#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qsvaR
// The qsvaR package contains functions for removing the effect of degration in rna-seq data from postm
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qsvaR/inst/doc/Intro_qsvaR.R
// Upstream  : BiocFileCache, RefManageR, knitr, limma, rmarkdown
// Downstream: none
//
// Install: BiocManager::install("qsvaR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSVAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qsvar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qsvar:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qsvar:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qsvar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qsvar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qsvar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qsvaR)
    library(BiocFileCache)
    library(DEqual)
    library(PrintBibliography)
    library(jsonlite)

    # --- Identify Degraded Transcripts [] ---
    # Key functions: getDegTx
    DegTx <- getDegTx(
        rse_tx = rse_tx,
        type = "cell_component"
    )
    deg_summary <- list(
        dimensions = dim(DegTx),
        features = head(rownames(DegTx))
    )

    # --- Calculate Quality Surrogate Variables [] ---
    # Key functions: getPCs, k_qsvs, get_qsvs
    pcTx <- getPCs(
        rse_tx = DegTx,
        assayname = "tpm"
    )
    mod <- model.matrix(
        ~ Dx + Age + Sex + Race + Region,
        data = colData(rse_tx)
    )
    k <- k_qsvs(
        rse_tx = DegTx,
        mod = mod,
        assayname = "tpm"
    )
    qsvs <- get_qsvs(
        qsvPCs = pcTx,
        k = k
    )

    # --- Wrapper Quality Surrogate Variable Analysis [] ---
    # Key functions: qSVA
    mod <- model.matrix(
        ~ Dx + Age + Sex + Race + Region,
        data = colData(rse_tx)
    )
    qsvs_wrapper <- qSVA(
        rse_tx = rse_tx,
        type = "cell_component",
        mod = mod,
        assayname = "tpm"
    )

    # --- Differential Expression Analysis [] ---
    # Key functions: assays, rowData
    rse_tx_filtered <- rse_tx[rowData(rse_tx)$passExprsCut, ]
    mod_qSVA <- cbind(mod, qsvs)
    txExprs <- log2(assays(rse_tx_filtered)$tpm + 1)
    fitTx <- limma::lmFit(txExprs, mod_qSVA)
    eBTx <- limma::eBayes(fitTx)
    sigTx <- limma::topTable(
        eBTx,
        coef = 2,
        p.value = 1,
        number = nrow(rse_tx_filtered)
    )

    # --- Quality Control and Evaluation [] ---
    # Key functions: DEqual
    DE_noqsv <- data.frame(
        t = sigTx_noqsv$t,
        row.names = rownames(sigTx_noqsv)
    )
    DE_qsv <- data.frame(
        t = sigTx$t,
        row.names = rownames(sigTx)
    )
    DEqual(DE_noqsv)
    DEqual(DE_qsv)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qsvar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qsvar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qsvar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QSVAR:", paste0("    qsvar: ", packageVersion("qsvaR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qsvar_results.csv
    touch ${prefix}_qsvar_output.rds
    echo "BIOC_QSVAR:" > versions.yml
    echo "    qsvar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QSVAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QSVAR(ch_input)

    emit:
    results  = BIOC_QSVAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QSVAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QSVAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QSVAR.out.versions  // channel: path(versions.yml)
}
