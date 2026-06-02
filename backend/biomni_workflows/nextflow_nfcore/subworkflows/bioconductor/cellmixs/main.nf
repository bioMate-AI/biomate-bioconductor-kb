#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CellMixS
// CellMixS provides metrics and functions to evaluate batch effects, data integration and batch effect
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CellMixS/inst/doc/CellMixS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CellMixS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLMIXS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellmixs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellmixs:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellmixs:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellmixs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellmixs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellmixs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CellMixS)
    library(jsonlite)

    # --- Log-normalize count data [] ---
    # Key functions: reducedDimNames, cms, logNormCounts, removeBatchEffect, assay
    reducedDimNames(sce20)
    # --- VisGroup analysis [] ---
    # Key functions: visGroup, plot_grid, cms, visHist, map, bind_cols, visMetric, visOverview
    (Important: List names need to correspond to batch levels! See ?ldfDiff)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellmixs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellmixs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellmixs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLMIXS:", paste0("    cellmixs: ", packageVersion("CellMixS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellmixs_results.csv
    touch ${prefix}_cellmixs_output.rds
    echo "BIOC_CELLMIXS:" > versions.yml
    echo "    cellmixs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLMIXS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLMIXS(ch_input)

    emit:
    results  = BIOC_CELLMIXS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLMIXS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLMIXS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLMIXS.out.versions  // channel: path(versions.yml)
}
