#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dce
// Compute differential causal effects (dce) on (biological) networks. Given observational samples from
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dce/inst/doc/dce.R
// Upstream  : SummarizedExperiment, TCGAutils, cowplot, curatedTCGAData, ggplot2
// Downstream: none
//
// Install: BiocManager::install("dce")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dce"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dce:1.13.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dce:1.13.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dce_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dce_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dce_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dce)
    library(TCGAsplitAssays)
    library(jsonlite)

    # --- Pathway Retrieval [] ---
    # Key functions: get_pathways
    pathways <- get_pathways(pathway_list = list(kegg = c("Breast cancer")))
    brca_pathway <- pathways[[1]]$graph


    # --- Differential Causal Effect Estimation [] ---
    # Key functions: dce
    res <- dce::dce(graph_wt, X_wt, X_mt)
    df_dce <- as.data.frame(res)


    # --- Ground Truth Evaluation [] ---
    # Key functions: trueEffects
    dce_gt <- trueEffects(graph_mt) - trueEffects(graph_wt)
    dce_gt_ind <- which(dce_gt != 0, arr.ind = TRUE)


    # --- Network Visualisation [] ---
    # Key functions: plot_network
    plot_network(
        as(graph_wt, "matrix"),
        labelsize = 0,
        arrow_size = 0.01
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dce_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dce_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dce_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DCE:", paste0("    dce: ", packageVersion("dce"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dce_results.csv
    touch ${prefix}_dce_output.rds
    echo "BIOC_DCE:" > versions.yml
    echo "    dce: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DCE(ch_input)

    emit:
    results  = BIOC_DCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DCE.out.versions  // channel: path(versions.yml)
}
