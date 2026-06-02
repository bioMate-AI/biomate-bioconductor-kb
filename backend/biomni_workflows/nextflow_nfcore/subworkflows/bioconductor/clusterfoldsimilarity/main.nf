#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClusterFoldSimilarity
// This package calculates a similarity coefficient using the fold changes of shared features (e.g. gen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClusterFoldSimilarity/inst/doc/ClusterFoldSimilarity.R
// Upstream  : Seurat, dplyr, scRNAseq
// Downstream: none
//
// Install: BiocManager::install("ClusterFoldSimilarity")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTERFOLDSIMILARITY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterfoldsimilarity"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clusterfoldsimilarity:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clusterfoldsimilarity:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clusterfoldsimilarity_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterfoldsimilarity_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterfoldsimilarity_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CreateSeuratObject)
    library(MuraroPancreasData)
    library(jsonlite)

    # --- Muraro Pancreas Data [] ---
    # Key functions: MuraroPancreasData, colData, CreateSeuratObject
    library(Seurat)
    library(scRNAseq)
    library(dplyr)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clusterfoldsimilarity_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clusterfoldsimilarity_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clusterfoldsimilarity_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERFOLDSIMILARITY:", paste0("    clusterfoldsimilarity: ", packageVersion("ClusterFoldSimilarity"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clusterfoldsimilarity_results.csv
    touch ${prefix}_clusterfoldsimilarity_output.rds
    echo "BIOC_CLUSTERFOLDSIMILARITY:" > versions.yml
    echo "    clusterfoldsimilarity: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERFOLDSIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERFOLDSIMILARITY(ch_input)

    emit:
    results  = BIOC_CLUSTERFOLDSIMILARITY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERFOLDSIMILARITY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERFOLDSIMILARITY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERFOLDSIMILARITY.out.versions  // channel: path(versions.yml)
}
