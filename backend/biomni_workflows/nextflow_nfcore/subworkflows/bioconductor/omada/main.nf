#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omada
// Symptomatic heterogeneity in complex diseases reveals differences in molecular states that need to b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omada/inst/doc/omada-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("omada")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMADA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omada"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omada:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omada:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omada_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omada_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omada_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(omada)
    library(jsonlite)

    # --- Clustering Method Selection [] ---
    # Key functions: clusteringMethodSelection, get_partition_agreement_scores, plot_partition_agreement
    method.results <- clusteringMethodSelection(toy_genes, method.upper.k = 3, 
                                                number.of.comparisons = 2)
    pa.scores <- get_partition_agreement_scores(method.results)
    plot_partition_agreement(method.results)


    # --- Feature Selection [] ---
    # Key functions: featureSelection, get_average_feature_k_stabilities, get_optimal_features, plot_average_stabilities
    feature.selection.results <- featureSelection(toy_genes, min.k = 3, 
                                                   max.k = 6, step = 3)
    feature.selection.scores <- get_average_feature_k_stabilities(
        feature.selection.results
    )
    optimal.features <- get_optimal_features(feature.selection.results)
    plot_average_stabilities(feature.selection.results)


    # --- Cluster Voting and Optimal Clustering [] ---
    # Key functions: clusterVoting, get_internal_metric_scores, optimalClustering, get_optimal_memberships, plot_vote_frequencies
    cluster.voting.results <- clusterVoting(toy_genes, 4, 8, "sc")
    internal.metric.scores <- get_internal_metric_scores(
        cluster.voting.results
    )
    plot_vote_frequencies(cluster.voting.results)
    sample.memberships <- optimalClustering(toy_genes, 4, "spectral")
    memberships <- get_optimal_memberships(sample.memberships)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omada_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omada_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omada_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMADA:", paste0("    omada: ", packageVersion("omada"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omada_results.csv
    touch ${prefix}_omada_output.rds
    echo "BIOC_OMADA:" > versions.yml
    echo "    omada: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMADA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMADA(ch_input)

    emit:
    results  = BIOC_OMADA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMADA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMADA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMADA.out.versions  // channel: path(versions.yml)
}
