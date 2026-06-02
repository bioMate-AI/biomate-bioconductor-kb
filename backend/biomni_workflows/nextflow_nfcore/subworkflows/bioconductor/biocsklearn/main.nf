#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiocSklearn
// This package provides interfaces to selected sklearn elements, and demonstrates fault tolerant use o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiocSklearn/inst/doc/BiocSklearn.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("BiocSklearn")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCSKLEARN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocsklearn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocsklearn:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocsklearn:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocsklearn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocsklearn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocsklearn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocSklearn)
    library(jsonlite)

    # --- Principal Component Analysis [] ---
    # Key functions: skPCA
    iris_matrix <- data.matrix(iris[, 1:4])
    pca_model <- skPCA(iris_matrix, n_components = 3L)
    pca_summary <- summary(pca_model)


    # --- Dimensionality Reduction Retrieval [] ---
    # Key functions: skPCA, getTransformed
    iris_matrix <- data.matrix(iris[, 1:4])
    pca_model <- skPCA(iris_matrix, n_components = 2L)
    transformed_coords <- getTransformed(pca_model)
    coords_dimensions <- dim(transformed_coords)
    coords_preview <- head(transformed_coords)


    # --- Incremental PCA for Large Datasets [] ---
    # Key functions: skIncrPCA, getTransformed
    iris_matrix <- data.matrix(iris[, 1:4])
    inc_pca_model <- skIncrPCA(
        iris_matrix, 
        n_components = 2L, 
        batch_size = 10L
    )
    inc_transformed <- getTransformed(inc_pca_model)


    # --- Clustering with KMeans [] ---
    # Key functions: skKMeans
    iris_matrix <- data.matrix(iris[, 1:4])
    kmeans_model <- skKMeans(iris_matrix, n_clusters = 3L)
    cluster_assignments <- kmeans_model$labels_
    cluster_centers <- kmeans_model$cluster_centers_

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocsklearn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocsklearn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocsklearn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCSKLEARN:", paste0("    biocsklearn: ", packageVersion("BiocSklearn"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocsklearn_results.csv
    touch ${prefix}_biocsklearn_output.rds
    echo "BIOC_BIOCSKLEARN:" > versions.yml
    echo "    biocsklearn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCSKLEARN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCSKLEARN(ch_input)

    emit:
    results  = BIOC_BIOCSKLEARN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCSKLEARN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCSKLEARN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCSKLEARN.out.versions  // channel: path(versions.yml)
}
