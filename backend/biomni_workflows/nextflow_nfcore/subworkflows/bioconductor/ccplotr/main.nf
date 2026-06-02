#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CCPlotR
// CCPlotR is an R package for visualising results from tools that predict cell-cell interactions from 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CCPlotR/inst/doc/CCPlotR_visualisations.R
// Upstream  : ggplot2, patchwork
// Downstream: none
//
// Install: BiocManager::install("CCPlotR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CCPLOTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ccplotr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ccplotr:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ccplotr:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ccplotr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ccplotr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ccplotr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CCPlotR)
    library(jsonlite)

    # --- Cc heatmap analysis [] ---
    # Key functions: cc_heatmap, cc_dotplot, cc_network, cc_circos, cc_arrow, cc_sigmoid, show_col
    cc_circos(toy_data, option = "B", n_top_ints = 10, cex = 0.75)
    cc_circos(toy_data, option = "C", n_top_ints = 15, exp_df = toy_exp, cell_cols = c(`B` = "hotpink", `NK` = "orange", `CD8 T` = "cornflowerblue"), palette = "PuRd", cex = 0.75)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ccplotr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ccplotr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ccplotr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CCPLOTR:", paste0("    ccplotr: ", packageVersion("CCPlotR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ccplotr_results.csv
    touch ${prefix}_ccplotr_output.rds
    echo "BIOC_CCPLOTR:" > versions.yml
    echo "    ccplotr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CCPLOTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CCPLOTR(ch_input)

    emit:
    results  = BIOC_CCPLOTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CCPLOTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CCPLOTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CCPLOTR.out.versions  // channel: path(versions.yml)
}
