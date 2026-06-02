#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: recount
// Explore and download data from the recount project available at https://jhubiostatistics.shinyapps.i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/recount/inst/doc/SRP009615-results.R
// Upstream  : DESeq2, DT, GenomeInfoDb, GenomicRanges, RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("recount")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECOUNT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-recount"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-recount:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-recount:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_recount_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_recount_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_recount_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(recount)
    library(PrintBibliography)
    library(jsonlite)

    # --- Quality Control and PCA [] ---
    # Key functions: rlog, plotPCA
    rld <- rlog(dds, fitType = "mean")
    plotPCA(rld, intgroup = "group")


    # --- Differential Expression Visualization [] ---
    # Key functions: plotMA
    plotMA(res, alpha = metadata(res)$alpha,
        main = paste("MA plot with alpha =", metadata(res)$alpha))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_recount_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_recount_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_recount_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RECOUNT:", paste0("    recount: ", packageVersion("recount"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recount_results.csv
    touch ${prefix}_recount_output.rds
    echo "BIOC_RECOUNT:" > versions.yml
    echo "    recount: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RECOUNT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RECOUNT(ch_input)

    emit:
    results  = BIOC_RECOUNT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RECOUNT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RECOUNT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RECOUNT.out.versions  // channel: path(versions.yml)
}
