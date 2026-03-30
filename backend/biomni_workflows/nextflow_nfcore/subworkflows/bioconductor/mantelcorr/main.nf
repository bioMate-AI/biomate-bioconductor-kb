#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MantelCorr
// Computes Mantel cluster correlations from a (p x n) numeric data matrix (e.g. microarray gene-expres
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MantelCorr/inst/doc/MantelCorrVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MantelCorr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MANTELCORR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mantelcorr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mantelcorr:1.76.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mantelcorr:1.76.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mantelcorr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mantelcorr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mantelcorr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ClusterGeneList)
    library(ClusterList)
    library(DistMatrices)
    library(GetClusters)
    library(MantelCorrs)
    library(PermutationTest)
    library(jsonlite)

    # --- Preliminaries [] ---
    # Key functions: data
    library(MantelCorr)
    data(GolubTrain)
    dim(GolubTrain)
    data <- GolubTrain
    # --- Getclusters [] ---
    # Key functions: GetClusters
    kmeans.result <- GetClusters(data, 500, 100)
    # --- Distmatrices [] ---
    # Key functions: DistMatrices
    DistMatrices.result <- DistMatrices(data, kmeans.result$clusters)
    # --- Mantelcorrs [] ---
    # Key functions: MantelCorrs
    MantelCorrs.result <- MantelCorrs(DistMatrices.result$Dfull, DistMatrices.result$Dsubsets)
    # --- Permutationtest [] ---
    # Key functions: PermutationTest
    permuted.pval <- PermutationTest(DistMatrices.result$Dfull, DistMatrices.result$Dsubsets, 100, 38, 0.05)
    # --- Clusterlist [] ---
    # Key functions: ClusterList
    ClusterLists <- ClusterList(permuted.pval, kmeans.result$cluster.sizes, MantelCorrs.result)
    # --- Clustergenelist [] ---
    # Key functions: ClusterGeneList
    ClusterGenes <- ClusterGeneList(kmeans.result$clusters, ClusterLists$SignificantClusters, data)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mantelcorr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mantelcorr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mantelcorr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MANTELCORR:", paste0("    mantelcorr: ", packageVersion("MantelCorr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mantelcorr_results.csv
    touch ${prefix}_mantelcorr_output.rds
    echo "BIOC_MANTELCORR:" > versions.yml
    echo "    mantelcorr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MANTELCORR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MANTELCORR(ch_input)

    emit:
    results  = BIOC_MANTELCORR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MANTELCORR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MANTELCORR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MANTELCORR.out.versions  // channel: path(versions.yml)
}
