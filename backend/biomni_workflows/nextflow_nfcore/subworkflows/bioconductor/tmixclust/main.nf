#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TMixClust
// Implementation of a clustering method for time series gene expression data based on mixed-effects mo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TMixClust/inst/doc/TMixClust.R
// Upstream  : SPEM
// Downstream: none
//
// Install: BiocManager::install("TMixClust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TMIXCLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tmixclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tmixclust:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tmixclust:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tmixclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tmixclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tmixclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TMixClust)
    library(jsonlite)

    # --- plot_time_series_df [] ---
    # Key functions: plot_time_series_df
    library(TMixClust)
    data(toy_data_df)
    print(head(toy_data_df))
    # --- plot_silhouette [] ---
    # Key functions: plot_silhouette
    plot_silhouette(best_clust_toy_obj)
    # --- generate_ T Mix Clust_report [] ---
    # Key functions: generate_TMixClust_report
    (not executed here)
    generate_TMixClust_report(cluster_obj)
    # --- plot_time_series_df [] ---
    # Key functions: plot_time_series_df

    # --- to Latex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tmixclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tmixclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tmixclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TMIXCLUST:", paste0("    tmixclust: ", packageVersion("TMixClust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tmixclust_results.csv
    touch ${prefix}_tmixclust_output.rds
    echo "BIOC_TMIXCLUST:" > versions.yml
    echo "    tmixclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TMIXCLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TMIXCLUST(ch_input)

    emit:
    results  = BIOC_TMIXCLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TMIXCLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TMIXCLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TMIXCLUST.out.versions  // channel: path(versions.yml)
}
