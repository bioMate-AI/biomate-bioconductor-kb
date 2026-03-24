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

    # --- example random dataset [] ---
    # Key functions: make_random_xina_data
    random_data_info <- make_random_xina_data()
    # --- XINA clustering [] ---
    # Key functions: xina_clustering
    clustering_result <- xina_clustering(data_files, data_column=data_column, nClusters=20)
    # --- XINA with k [] ---
    # Key functions: xina_clustering
    clustering_result_km <- xina_clustering(data_files, data_column=data_column, nClusters=20, chosen_model='kmeans')
    # --- XINA clustering plot [] ---
    # Key functions: theme, plot_clusters
    library(ggplot2)
    theme1 <- theme(title=element_text(size=8, face='bold'),
    axis.text.x = element_text(size=7),
    # --- XINA condition composition [] ---
    # Key functions: theme, plot_condition_compositions
    theme2 <- theme(legend.key.size = unit(0.3, "cm"),
    legend.text=element_text(size=5),
    title=element_text(size=7, face='bold'))
    # --- XINA comigration search [] ---
    # Key functions: alluvial_enriched
    classes <- as.vector(clustering_result$condition)
    all_cor <- alluvial_enriched(clustering_result, classes)
    head(all_cor)
    # --- XINA comigration search with comigration size filter [] ---
    # Key functions: alluvial_enriched
    cor_bigger_than_5 <- alluvial_enriched(clustering_result, classes, comigration_size=5)
    head(cor_bigger_than_5)
    # --- STRING DB set up [] ---
    # Key functions: xina_analysis
    library(STRINGdb)
    string_db <- STRINGdb$new( version="10", species=9606, score_threshold=0, input_directory="" )
    xina_result <- xina_analysis(clustering_result, string_db)
    # --- plotting PPI networks of all the clusters [] ---
    # Key functions: xina_plot_all
    xina_plot_all(xina_result, clustering_result)

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
