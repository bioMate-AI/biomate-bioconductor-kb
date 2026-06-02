#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NetActivity
// #' NetActivity enables to compute gene set scores from previously trained sparsely-connected autoenc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NetActivity/inst/doc/NetActivity.R
// Upstream  : DESeq2, Fletcher2013a, airway, limma, tidyverse
// Downstream: none
//
// Install: BiocManager::install("NetActivity")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETACTIVITY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-netactivity"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-netactivity:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-netactivity:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_netactivity_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_netactivity_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_netactivity_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NetActivity)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: gather, assay, ggplot, geom_boxplot

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_boxplot, theme_bw, ylab

    # --- Custom ggplot2 visualization [] ---
    # Key functions: rowData, ggplot, geom_bar, theme_bw, ylab
    weights <- rowData(scores)["GO:1990440", ]$Weights_SYMBOL[[1]]
    data.frame(weight = weights, gene = names(weights)) %>%
    mutate(Direction = ifelse(weight > 0, "Positive", "Negative")) %>%

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_netactivity_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_netactivity_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_netactivity_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NETACTIVITY:", paste0("    netactivity: ", packageVersion("NetActivity"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netactivity_results.csv
    touch ${prefix}_netactivity_output.rds
    echo "BIOC_NETACTIVITY:" > versions.yml
    echo "    netactivity: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NETACTIVITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NETACTIVITY(ch_input)

    emit:
    results  = BIOC_NETACTIVITY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NETACTIVITY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NETACTIVITY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NETACTIVITY.out.versions  // channel: path(versions.yml)
}
