#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpatialDecon
// Using spatial or bulk gene expression data, estimates abundance of mixed cell types within each obse
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpatialDecon/inst/doc/SpatialDecon_vignette.R
// Upstream  : Seurat, SeuratObject
// Downstream: none
//
// Install: BiocManager::install("SpatialDecon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALDECON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialdecon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialdecon:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialdecon:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialdecon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialdecon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialdecon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpatialDecon)
    library(CreateSeuratObject)
    library(Idents)
    library(TIL_barplot)
    library(jsonlite)

    # --- Profile Matrix Creation [] ---
    # Key functions: create_profile_matrix
    custom_mtx <- create_profile_matrix(
        mtx = mini_singleCell_dataset$mtx,
        cellAnnots = mini_singleCell_dataset$annots,
        cellTypeCol = "LabeledCellType",
        cellNameCol = "CellID",
        matrixName = "custom_mini_colon",
        outDir = NULL,
        normalize = FALSE,
        minCellNum = 5,
        minGenes = 10,
        scalingFactor = 5,
        discardCellTypes = TRUE
    )


    # --- Spatial Deconvolution [] ---
    # Key functions: spatialdecon
    res <- spatialdecon(
        norm = norm,
        bg = bg,
        X = safeTME,
        align_genes = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialdecon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialdecon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialdecon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALDECON:", paste0("    spatialdecon: ", packageVersion("SpatialDecon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialdecon_results.csv
    touch ${prefix}_spatialdecon_output.rds
    echo "BIOC_SPATIALDECON:" > versions.yml
    echo "    spatialdecon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALDECON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALDECON(ch_input)

    emit:
    results  = BIOC_SPATIALDECON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALDECON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALDECON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALDECON.out.versions  // channel: path(versions.yml)
}
