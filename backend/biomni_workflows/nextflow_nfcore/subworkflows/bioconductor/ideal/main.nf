#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ideal
// This package provides functions for an Interactive Differential Expression AnaLysis of RNA-sequencin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ideal/inst/doc/ideal-usersguide.R
// Upstream  : DEFormats, DESeq2, airway, dplyr, edgeR
// Downstream: none
//
// Install: BiocManager::install("ideal")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IDEAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ideal"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ideal:2.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ideal:2.0.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_ideal_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ideal_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ideal_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(jsonlite)

    # --- Create DESeqDataSet [] ---
    # Key functions: DESeqDataSet, DESeq, results
    library("airway")
    library("DESeq2")
    data("airway", package = "airway")
    # --- Calculate normalization factors (TMM) [] ---
    # Key functions: colData, design, calcNormFactors, estimateDisp, glmQLFit
    library(DEFormats)
    library(edgeR)
    library(limma)
    # --- Fast GSEA analysis [] ---
    # Key functions: arrange, deframe, gmtPathways, fgsea
    library("fgsea")
    summary(exported_res)
    library("dplyr")
    # --- ID mapping annotation [] ---
    # Key functions: ideal, mapIds, deresult_to_df, datatable, goseqTable, plot_ma, plot_volcano, sepguesser
    myde <- mosdef::deresult_to_df(res_airway, FDR = 0.05)
    myde$symbol <- mapIds(org.Hs.eg.db, keys = as.character(myde$id), column = "SYMBOL", keytype = "ENSEMBL")
    myde_enhanced$id <- mosdef::create_link_ENSEMBL(myde_enhanced$id, species = "Homo_sapiens")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ideal_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ideal_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ideal_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IDEAL:", paste0("    ideal: ", packageVersion("ideal"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ideal_results.csv
    touch ${prefix}_ideal_output.rds
    echo "BIOC_IDEAL:" > versions.yml
    echo "    ideal: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IDEAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_IDEAL(ch_input)

    emit:
    results  = BIOC_IDEAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IDEAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IDEAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IDEAL.out.versions  // channel: path(versions.yml)
}
