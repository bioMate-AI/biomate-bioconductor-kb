#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LymphoSeq
// This R package analyzes high-throughput sequencing of T and B cell receptor complementarity determin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LymphoSeq/inst/doc/LymphoSeq.R
// Upstream  : RColorBrewer, ggplot2, grDevices, pheatmap, reshape
// Downstream: none
//
// Install: BiocManager::install("LymphoSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LYMPHOSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lymphoseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lymphoseq:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lymphoseq:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lymphoseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lymphoseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lymphoseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LymphoSeq)
    library(jsonlite)

    # --- Mergefiles [] ---
    # Key functions: mergeFiles
    ---------------------------------------------------------------------
    TRB_949_Merged <- mergeFiles(samples = c("TRB_CD4_949", "TRB_CD8_949"),
                                    file.list = TCRB.list)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lymphoseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lymphoseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lymphoseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LYMPHOSEQ:", paste0("    lymphoseq: ", packageVersion("LymphoSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lymphoseq_results.csv
    touch ${prefix}_lymphoseq_output.rds
    echo "BIOC_LYMPHOSEQ:" > versions.yml
    echo "    lymphoseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LYMPHOSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LYMPHOSEQ(ch_input)

    emit:
    results  = BIOC_LYMPHOSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LYMPHOSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LYMPHOSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LYMPHOSEQ.out.versions  // channel: path(versions.yml)
}
