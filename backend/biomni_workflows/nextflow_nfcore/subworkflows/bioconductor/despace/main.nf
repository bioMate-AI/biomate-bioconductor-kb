#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DESpace
// Intuitive framework for identifying spatially variable genes (SVGs) via edgeR, a popular method for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DESpace/inst/doc/DESpace.R
// Upstream  : SpatialExperiment, ggforce, ggplot2
// Downstream: none
//
// Install: BiocManager::install("DESpace")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DESPACE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-despace"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-despace:1.6.1--r44_0' :
        'quay.io/biocontainers/bioconductor-despace:1.6.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_despace_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_despace_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_despace_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESpace)
    library(DESpace_test)
    library(ExperimentHub)
    library(FeaturePlot)
    library(jsonlite)

    # --- Individual Cluster Testing [] ---
    # Key functions: individual_test
    cluster_results <- DESpace::individual_test(
        spe = spe3,
        edgeR_y = results$estimated_y,
        spatial_cluster = spatial_cluster
    )


    # --- Results Aggregation [] ---
    # Key functions: top_results
    merge_res <- DESpace::top_results(
        results$gene_results,
        cluster_results,
        select = "FDR"
    )


    # --- Spatial Feature Visualization [] ---
    # Key functions: FeaturePlot
    feature <- results$gene_results$gene_id[1:3]
    DESpace::FeaturePlot(
        spe = spe3,
        feature = feature,
        coordinates = coordinates,
        ncol = 3,
        title = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_despace_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_despace_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_despace_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DESPACE:", paste0("    despace: ", packageVersion("DESpace"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_despace_results.csv
    touch ${prefix}_despace_output.rds
    echo "BIOC_DESPACE:" > versions.yml
    echo "    despace: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DESPACE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DESPACE(ch_input)

    emit:
    results  = BIOC_DESPACE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DESPACE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DESPACE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DESPACE.out.versions  // channel: path(versions.yml)
}
