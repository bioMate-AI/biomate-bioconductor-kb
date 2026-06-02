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
    library(BiocFileCache)
    library(DEqual)
    library(PrintBibliography)
    library(jsonlite)

    # --- "install" [] ---
    # Key functions: valid

    # --- "Download demo dataset" [] ---
    # Key functions: BiocFileCache, bfcrpath
    bfc <- BiocFileCache::BiocFileCache()
    # --- "Get Degraded Transcripts" [] ---
    # Key functions: getDegTx
    DegTx <- getDegTx(rse_tx, type = "cell_component")
    dim(DegTx)
    # --- "getPCs demo" [] ---
    # Key functions: getPCs
    pcTx <- getPCs(rse_tx = DegTx, assayname = "tpm")
    # --- "k qsvs demo" [] ---
    # Key functions: k_qsvs

    # --- "get qsvs demo" [] ---
    # Key functions: get_qsvs
    qsvs <- get_qsvs(qsvPCs = pcTx, k = k)
    dim(qsvs)
    # --- "wrapper function" [] ---
    # Key functions: qSVA
    random seed with the set.seed() function. Internally, we are using
    sva::num.sv() which needs a random seed to ensure reproducibility of the
    set.seed(20230621)
    # --- "perform DE" [] ---
    # Key functions: lmFit, eBayes, topTable
    rse_tx <- rse_tx[rowData(rse_tx)$passExprsCut, ]
    mod_qSVA <- cbind(mod, qsvs)
    txExprs <- log2(assays(rse_tx)$tpm + 1)
    # --- "perform DE without qSVs" [] ---
    # Key functions: lmFit, eBayes, topTable
    txExprs_noqsv <- log2(assays(rse_tx)$tpm + 1)
    fitTx_noqsv <- lmFit(txExprs_noqsv, mod)
    eBTx_noqsv <- eBayes(fitTx_noqsv)
    # --- "Generate DEqual without qSVs" [] ---
    # Key functions: DEqual
    Generate a DEqual() plot using the model results without qSVs
    DEqual(DE_noqsv)
    # --- "Generate DEqual with qSVs" [] ---
    # Key functions: DEqual
    Generate a DEqual() plot using the model results with qSVs
    DEqual(DE)
    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("Intro_qsvaR.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- diff [] ---
    # Key functions: diff
    totalTime <- diff(c(startTime, Sys.time()))
    round(totalTime, digits = 3)
    # --- session_info [] ---
    # Key functions: session_info
    library("sessioninfo")
    options(width = 120)
    session_info()
    # --- Print Bibliography [] ---
    # Key functions: PrintBibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

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
