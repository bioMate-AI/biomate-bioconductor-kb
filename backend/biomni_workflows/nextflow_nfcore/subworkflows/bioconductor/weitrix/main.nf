#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: weitrix
// Data type and tools for working with matrices having precision weights and missing data. This packag
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/weitrix/inst/doc/V2_tail_length.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("weitrix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WEITRIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-weitrix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-weitrix:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-weitrix:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(marraylm)

    output:
    tuple val(meta), path("${meta.id}_weitrix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_weitrix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_weitrix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(weitrix)
    library(jsonlite)

    # --- Linear model fit (limma) [] ---
    # Key functions: weitrix_elist, lmFit, eBayes, topTable, makeContrasts, weitrix_confects

    # --- Custom ggplot2 visualization [] ---
    # Key functions: rowData, weitrix_x, weitrix_weights, ggplot, matrix_long, geom_hline, geom_line, geom_point
    matrix_long(comp$col[,-1], row_info=samples, varnames=c("sample","component")) %>%
    ggplot(aes(x=time, y=value, color=strain, group=strain)) +
    geom_hline(yintercept=0) +
    # --- Feature metadata inspection [] ---
    # Key functions: column_to_rownames, extract, rowMeans, as_weitrix, rowData, colData, weitrix_components, weitrix_calibrate_all
    weitrix_calplot(unwei, fit, covar=log(weitrix_weights(wei)), guides=FALSE) + labs(title="Unweighted\n") |
    weitrix_calplot(wei, fit, covar=log(weitrix_weights(wei)), guides=FALSE) + labs(title="Weighted by\nread count") |
    weitrix_calplot(cal, fit, covar=log(weitrix_weights(wei)), guides=FALSE) + labs(title="Calibrated\n")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_weitrix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_weitrix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_weitrix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_WEITRIX:", paste0("    weitrix: ", packageVersion("weitrix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weitrix_results.csv
    touch ${prefix}_weitrix_output.rds
    echo "BIOC_WEITRIX:" > versions.yml
    echo "    weitrix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WEITRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(marraylm) ]

    main:
    BIOC_WEITRIX(ch_input)

    emit:
    results  = BIOC_WEITRIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WEITRIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WEITRIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WEITRIX.out.versions  // channel: path(versions.yml)
}
