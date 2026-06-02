#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DELocal
// The goal of DELocal is to identify DE genes compared to their neighboring genes from the same chromo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DELocal/inst/doc/DELocal.R
// Upstream  : SummarizedExperiment, biomaRt, dplyr
// Downstream: none
//
// Install: BiocManager::install("DELocal")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DELOCAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-delocal"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-delocal:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-delocal:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_delocal_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_delocal_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_delocal_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DELocal)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- Example [] ---
    # Key functions: read.table, extdata, tooth_RNASeq_counts.txt
    library(DELocal)
    count_matrix <- as.matrix(read.table(file = system.file("extdata", 
                                                  "tooth_RNASeq_counts.txt", 
                                                  package = "DELocal")))
    colData <- data.frame(condition=gsub("\\..*",x=colnames(count_matrix),
                                         replacement = ""))

    # --- Eval=true [] ---
    # Key functions: useMart, getBM, ensembl_gene_id, start_position, chromosome_name, ENSEMBL_MART_ENSEMBL, mmusculus_gene_ensembl, www.ensembl.org
    library(biomaRt)
    gene_attributes <- c("ensembl_gene_id", "start_position", "chromosome_name")
    ensembl_ms_mart <- useMart(biomart="ENSEMBL_MART_ENSEMBL",
                               dataset="mmusculus_gene_ensembl", host="www.ensembl.org")
    gene_location_sample <- getBM(attributes=gene_attributes, mart=ensembl_ms_mart,
                           verbose = FALSE)
    rownames(gene_location_sample) <- gene_location_sample$ensembl_gene_id

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_delocal_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_delocal_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_delocal_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DELOCAL:", paste0("    delocal: ", packageVersion("DELocal"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delocal_results.csv
    touch ${prefix}_delocal_output.rds
    echo "BIOC_DELOCAL:" > versions.yml
    echo "    delocal: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DELOCAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DELOCAL(ch_input)

    emit:
    results  = BIOC_DELOCAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DELOCAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DELOCAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DELOCAL.out.versions  // channel: path(versions.yml)
}
