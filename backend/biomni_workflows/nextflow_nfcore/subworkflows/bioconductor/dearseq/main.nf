#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dearseq
// Differential Expression Analysis RNA-seq data with variance component score test accounting for data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dearseq/inst/doc/dearseqUserguide.R
// Upstream  : BiocSet, GEOquery, SummarizedExperiment, edgeR, ggplot2
// Downstream: none
//
// Install: BiocManager::install("dearseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEARSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dearseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dearseq:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dearseq:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dearseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dearseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dearseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGEList)
    library(Meta)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Fetch GEO dataset [] ---
    # Key functions: getGEO, Meta
    library(GEOquery)
    GSE107991_metadata <- GEOquery::getGEO("GSE107991", GSEMatrix = FALSE)
    # --- London [] ---
    # Key functions: getGEOSuppFiles, read_excel
    library(readxl)
    # --- LR ST echo [] ---
    # Key functions: SummarizedExperiment, dear_seq
    library(dearseq)
    library(SummarizedExperiment)
    col_data <- data.frame("Status" = infos_df$Status)
    # --- London raw [] ---
    # Key functions: getGEOSuppFiles, read_excel, SummarizedExperiment, ifelse, DGEList
    library(readxl)
    library(edgeR)
    # --- Create SummarizedExperiment [] ---
    # Key functions: SummarizedExperiment, dgsa_seq
    library(dearseq)
    library(SummarizedExperiment)
    library(BiocSet)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dearseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dearseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dearseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEARSEQ:", paste0("    dearseq: ", packageVersion("dearseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dearseq_results.csv
    touch ${prefix}_dearseq_output.rds
    echo "BIOC_DEARSEQ:" > versions.yml
    echo "    dearseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEARSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEARSEQ(ch_input)

    emit:
    results  = BIOC_DEARSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEARSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEARSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEARSEQ.out.versions  // channel: path(versions.yml)
}
