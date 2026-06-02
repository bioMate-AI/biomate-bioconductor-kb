#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: velociraptor
// This package provides Bioconductor-friendly wrappers for RNA velocity calculations in single-cell RN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/velociraptor/inst/doc/velociraptor.R
// Upstream  : BiocStyle, ggplot2, knitr, scRNAseq, scater
// Downstream: OSCA.advanced
//
// Install: BiocManager::install("velociraptor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VELOCIRAPTOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-velociraptor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-velociraptor:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-velociraptor:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_velociraptor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_velociraptor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_velociraptor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(velociraptor)
    library(HermannSpermatogenesisData)
    library(jsonlite)

    # --- Velocity Embedding Projection [] ---
    # Key functions: embedVelocity
    tsne_coords <- SingleCellExperiment::reducedDim(sce, "TSNE")
    embedded_velo <- embedVelocity(
        tsne_coords,
        velo_out
    )


    # --- Velocity Grid Aggregation [] ---
    # Key functions: gridVectors
    grid_df <- gridVectors(
        sce,
        embedded_velo,
        use.dimred = "TSNE"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_velociraptor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_velociraptor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_velociraptor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VELOCIRAPTOR:", paste0("    velociraptor: ", packageVersion("velociraptor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_velociraptor_results.csv
    touch ${prefix}_velociraptor_output.rds
    echo "BIOC_VELOCIRAPTOR:" > versions.yml
    echo "    velociraptor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VELOCIRAPTOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VELOCIRAPTOR(ch_input)

    emit:
    results  = BIOC_VELOCIRAPTOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VELOCIRAPTOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VELOCIRAPTOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VELOCIRAPTOR.out.versions  // channel: path(versions.yml)
}
