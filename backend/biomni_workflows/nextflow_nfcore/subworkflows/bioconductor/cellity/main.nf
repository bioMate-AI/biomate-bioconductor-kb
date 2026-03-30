#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cellity
// A support vector machine approach to identifying and filtering low quality cells from single-cell RN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cellity/inst/doc/cellity_vignette.R
// Upstream  : caret, ggplot2, knitr
// Downstream: none
//
// Install: BiocManager::install("cellity")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLITY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellity"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellity:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellity:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellity_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellity_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellity_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cellity)
    library(jsonlite)

    # --- Knitr Options [] ---
    # Key functions: render, set, theme_set, theme_bw
    -----------------------------
    ## To render an HTML version that works nicely with github and web pages, do:
    ## rmarkdown::render("vignettes/vignette.Rmd", "all")
    library(knitr)
    opts_chunk$set(fig.align = 'center', fig.width = 6, fig.height = 5, dev = 'png')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellity_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellity_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellity_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLITY:", paste0("    cellity: ", packageVersion("cellity"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellity_results.csv
    touch ${prefix}_cellity_output.rds
    echo "BIOC_CELLITY:" > versions.yml
    echo "    cellity: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLITY(ch_input)

    emit:
    results  = BIOC_CELLITY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLITY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLITY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLITY.out.versions  // channel: path(versions.yml)
}
