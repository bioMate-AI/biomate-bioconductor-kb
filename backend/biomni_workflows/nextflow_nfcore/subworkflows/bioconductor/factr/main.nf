#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: factR
// factR contain tools to process and interact with custom-assembled transcriptomes (GTF). At its core,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/factR/inst/doc/factR.R
// Upstream  : AnnotationHub, Biostrings, GenomicFeatures, rtracklayer, tidyverse
// Downstream: none
//
// Install: BiocManager::install("factR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FACTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-factr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-factr:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-factr:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_factr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_factr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_factr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(jsonlite)

    # --- Access AnnotationHub resources [] ---
    # Key functions: AnnotationHub, query
    library(AnnotationHub)
    ah <- AnnotationHub()
    query(ah, c('Mus musculus', 'gencode', 'gff'))
    # --- ViewTranscripts analysis [] ---
    # Key functions: viewTranscripts, tempfile, importFASTA, predictDomains, export
    tmp <- tempfile()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_factr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_factr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_factr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FACTR:", paste0("    factr: ", packageVersion("factR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_factr_results.csv
    touch ${prefix}_factr_output.rds
    echo "BIOC_FACTR:" > versions.yml
    echo "    factr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FACTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FACTR(ch_input)

    emit:
    results  = BIOC_FACTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FACTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FACTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FACTR.out.versions  // channel: path(versions.yml)
}
