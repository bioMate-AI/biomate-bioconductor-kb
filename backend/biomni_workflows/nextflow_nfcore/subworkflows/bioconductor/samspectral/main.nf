#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SamSPECTRAL
// Samples large data such that spectral clustering is possible while preserving density information in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SamSPECTRAL/inst/doc/Clustering_by_SamSPECTRAL.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SamSPECTRAL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SAMSPECTRAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-samspectral"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-samspectral:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-samspectral:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_samspectral_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_samspectral_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_samspectral_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Building_Communities)
    library(Civilized_Spectral_Clustering)
    library(Conductance_Calculation)
    library(Connecting)
    library(SamSPECTRAL)
    library(jsonlite)

    # --- Community Building [] ---
    # Key functions: Building_Communities
    data(small_data)
    full <- small
    m <- 3000
    space.length <- 1
    community.weakness.threshold <- 1
    society <- Building_Communities(
        full, m, space.length,
        community.weakness.threshold
    )


    # --- Conductance Calculation [] ---
    # Key functions: Conductance_Calculation
    normal.sigma <- 250
    precision <- 6
    conductance <- Conductance_Calculation(
        full, normal.sigma, space.length,
        society, precision
    )


    # --- Civilized Spectral Clustering [] ---
    # Key functions: Civilized_Spectral_Clustering
    maximum.number.of.clusters <- 30
    clust_result <- Civilized_Spectral_Clustering(
        full, maximum.number.of.clusters,
        society, conductance, stabilizer = 1,
        eigenvalues.num = 50
    )
    eigen.values <- clust_result@eigen.space$values


    # --- Cluster Connecting and Post-processing [] ---
    # Key functions: Connecting
    labels.for_num.of.clusters <- clust_result@labels.for_num.of.clusters
    number.of.clusters <- clust_result@number.of.clusters
    separation.factor <- 0.5
    component.of <- Connecting(
        full, society, conductance, number.of.clusters,
        labels.for_num.of.clusters, separation.factor
    )$label

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_samspectral_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_samspectral_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_samspectral_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SAMSPECTRAL:", paste0("    samspectral: ", packageVersion("SamSPECTRAL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_samspectral_results.csv
    touch ${prefix}_samspectral_output.rds
    echo "BIOC_SAMSPECTRAL:" > versions.yml
    echo "    samspectral: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SAMSPECTRAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SAMSPECTRAL(ch_input)

    emit:
    results  = BIOC_SAMSPECTRAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SAMSPECTRAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SAMSPECTRAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SAMSPECTRAL.out.versions  // channel: path(versions.yml)
}
