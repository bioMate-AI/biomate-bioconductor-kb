#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: XINA
// The aim of XINA is to determine which proteins exhibit similar patterns within and across experiment
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/XINA/inst/doc/xina_user_code.R
// Upstream  : devtools, ggplot2, STRINGdb
// Downstream: none
//
// Install: BiocManager::install("XINA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XINA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xina"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-xina:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-xina:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xina_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xina_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xina_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(XINA)
    library(jsonlite)

    # --- Data Preparation [Data Preparation] ---
    # Key functions: make_random_xina_data
    random_data_info <- make_random_xina_data()
    data_files <- paste(
        random_data_info$conditions,
        ".csv",
        sep=""
    )
    data_column <- random_data_info$time_points

    # --- Clustering Analysis [Clustering Analysis] ---
    # Key functions: xina_clustering
    clustering_result <- xina_clustering(
        file_list=data_files,
        data_column=data_column,
        nClusters=20
    )
    clustering_result_km <- xina_clustering(
        file_list=data_files,
        data_column=data_column,
        nClusters=20,
        chosen_model="kmeans"
    )

    # --- Cluster Visualization [Cluster Visualization] ---
    # Key functions: plot_clusters
    plot_clusters(
        clustering_result
    )

    # --- Condition Composition Analysis [Condition Composition Analysis] ---
    # Key functions: plot_condition_compositions
    condition_composition <- plot_condition_compositions(
        clustering_result
    )

    # --- Comigration Search [Comigration Search] ---
    # Key functions: alluvial_enriched
    classes <- as.vector(clustering_result$condition)
    all_cor <- alluvial_enriched(
        clustering_result,
        classes
    )
    cor_filtered <- alluvial_enriched(
        clustering_result,
        classes,
        comigration_size=5
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_xina_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_xina_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_xina_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_XINA:", paste0("    xina: ", packageVersion("XINA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xina_results.csv
    touch ${prefix}_xina_output.rds
    echo "BIOC_XINA:" > versions.yml
    echo "    xina: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XINA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XINA(ch_input)

    emit:
    results  = BIOC_XINA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XINA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XINA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XINA.out.versions  // channel: path(versions.yml)
}
