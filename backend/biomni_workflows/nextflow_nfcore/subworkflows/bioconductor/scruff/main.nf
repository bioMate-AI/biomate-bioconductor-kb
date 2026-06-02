#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scruff
// A pipeline which processes single cell RNA-seq (scRNA-seq) reads from CEL-seq and CEL-seq2 protocols
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scruff/inst/doc/scruff.R
// Upstream  : BiocStyle, TENxBrainData
// Downstream: none
//
// Install: BiocManager::install("scruff")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRUFF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scruff"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scruff:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scruff:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scruff_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scruff_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scruff_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TENxBrainData)
    library(jsonlite)

    # --- Sample metadata inspection [] ---
    # Key functions: buildindex, scruff, qcplots, demultiplex, alignRsubread, countUMI, rview, gview
    g1 <- rview(bamExample, chr = "MT", start = start, end = end)
    g2 <- gview(gtf, chr = "MT", start = start, end = end)
    g <- ggbio::tracks(g1, g2, heights = c(4, 1), xlab = "chr MT")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scruff_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scruff_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scruff_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCRUFF:", paste0("    scruff: ", packageVersion("scruff"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scruff_results.csv
    touch ${prefix}_scruff_output.rds
    echo "BIOC_SCRUFF:" > versions.yml
    echo "    scruff: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCRUFF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCRUFF(ch_input)

    emit:
    results  = BIOC_SCRUFF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCRUFF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCRUFF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCRUFF.out.versions  // channel: path(versions.yml)
}
