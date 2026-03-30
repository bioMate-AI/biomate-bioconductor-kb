#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scider
// scider is a user-friendly R package providing functions to model the global density of cells in a sl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scider/inst/doc/scider_userGuide.R
// Upstream  : SpatialExperiment, ggplot2
// Downstream: none
//
// Install: BiocManager::install("scider")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCIDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scider"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scider:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scider:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scider_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scider_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scider_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scider)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("xenium_bc_spe")
    # --- Table [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    table(colData(spe)$cell_type)
    # --- Unique [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    coi <- unique(colData(spe)$cell_type)
    coi
    # --- Griddensity [] ---
    # Key functions: gridDensity, metadata
    ---------------------------------------------------------------------
    spe <- gridDensity(spe, coi = coi)
    names(metadata(spe))
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    metadata(spe)$grid_density
    # --- Findroi [] ---
    # Key functions: findROI, metadata
    ---------------------------------------------------------------------
    spe <- findROI(spe, coi = coi)
    metadata(spe)$roi
    # --- Cordensity [] ---
    # Key functions: corDensity
    ---------------------------------------------------------------------
    model_result <- corDensity(spe)
    # --- Getcontour [] ---
    # Key functions: getContour
    ---------------------------------------------------------------------
    spe <- getContour(spe, coi = "Breast cancer")
    # --- Allocatecells [] ---
    # Key functions: allocateCells
    ---------------------------------------------------------------------
    spe <- allocateCells(spe)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scider_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scider_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scider_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCIDER:", paste0("    scider: ", packageVersion("scider"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scider_results.csv
    touch ${prefix}_scider_output.rds
    echo "BIOC_SCIDER:" > versions.yml
    echo "    scider: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCIDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCIDER(ch_input)

    emit:
    results  = BIOC_SCIDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCIDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCIDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCIDER.out.versions  // channel: path(versions.yml)
}
