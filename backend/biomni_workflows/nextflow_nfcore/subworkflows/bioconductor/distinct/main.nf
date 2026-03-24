#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: distinct
// distinct is a statistical method to perform differential testing between two or more groups of distr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/distinct/inst/doc/distinct.R
// Upstream  : SingleCellExperiment, UpSetR, scater
// Downstream: none
//
// Install: BiocManager::install("distinct")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DISTINCT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-distinct"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-distinct:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-distinct:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_distinct_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_distinct_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_distinct_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(distinct)
    library(jsonlite)

    # --- visualize colData [] ---
    # Key functions: colData
    colData(Kang_subset)
    # --- col Data [] ---
    # Key functions: colData
    colData(Kang_subset)$stim = relevel(colData(Kang_subset)$stim, "stim")
    levels(colData(Kang_subset)$stim)
    res_2 = log2_FC(res = res,
    # --- top_results [] ---
    # Key functions: top_results
    top_results(res, cluster = "Dendritic cells")
    # --- plot densitied [] ---
    # Key functions: plot_densities
    plot_densities(x = Kang_subset,
    # --- plot densitied group level [] ---
    # Key functions: plot_densities
    plot_densities(x = Kang_subset,
    # --- plot_cdfs [] ---
    # Key functions: plot_cdfs
    plot_cdfs(x = Kang_subset,
    # --- plot Expression [] ---
    # Key functions: plotExpression, guides, theme
    genes = as.character(res$gene[sel_cluster & sel_genes])
    library(scater)
    plotExpression(Kang_subset[,sel_column],
    # --- UpsetR plot [] ---
    # Key functions: upset
    library(UpSetR)
    res_by_cluster = split( ifelse(res$p_adj.glb < 0.01, 1, 0), res$cluster_id)
    upset(data.frame(do.call(cbind, res_by_cluster)), nsets = 10, nintersects = 20)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_distinct_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_distinct_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_distinct_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DISTINCT:", paste0("    distinct: ", packageVersion("distinct"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_distinct_results.csv
    touch ${prefix}_distinct_output.rds
    echo "BIOC_DISTINCT:" > versions.yml
    echo "    distinct: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DISTINCT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DISTINCT(ch_input)

    emit:
    results  = BIOC_DISTINCT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DISTINCT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DISTINCT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DISTINCT.out.versions  // channel: path(versions.yml)
}
