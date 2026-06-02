#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HicAggR
// This package provides a set of functions useful in the analysis of 3D genomic interactions. It inclu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HicAggR/inst/doc/HicAggR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HicAggR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICAGGR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicaggr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicaggr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicaggr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicaggr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicaggr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicaggr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Aggregation)
    library(OrientateMatrix)
    library(jsonlite)

    # --- Aggregation [] ---
    # Key functions: Aggregation
    ---------------------------------------------------------------------
    aggreg.mtx <- Aggregation(
            ctrlMatrices=interactions_RFmatrix_ctrl.lst,
            aggFun="mean"
    )
    # --- Orientatematrix [] ---
    # Key functions: OrientateMatrix, Aggregation
    ---------------------------------------------------------------------
    oriented_interactions_RFmatrix_ctrl.lst <-
        OrientateMatrix(interactions_RFmatrix_ctrl.lst)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicaggr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicaggr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicaggr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICAGGR:", paste0("    hicaggr: ", packageVersion("HicAggR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicaggr_results.csv
    touch ${prefix}_hicaggr_output.rds
    echo "BIOC_HICAGGR:" > versions.yml
    echo "    hicaggr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICAGGR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICAGGR(ch_input)

    emit:
    results  = BIOC_HICAGGR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICAGGR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICAGGR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICAGGR.out.versions  // channel: path(versions.yml)
}
