#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hoodscanR
// hoodscanR is an user-friendly R package providing functions to assist cellular neighborhood analysis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hoodscanR/inst/doc/Quick_start.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("hoodscanR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HOODSCANR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hoodscanr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hoodscanr:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hoodscanr:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hoodscanr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hoodscanr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hoodscanr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hoodscanR)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: readHoodData
    ---------------------------------------------------------------------
    data("spe_test")
    spe <- readHoodData(spe, anno_col = "celltypes")
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    colData(spe)
    # --- Findnearcells [] ---
    # Key functions: findNearCells
    ---------------------------------------------------------------------
    fnc <- findNearCells(spe, k = 100)
    # --- Scanhoods [] ---
    # Key functions: scanHoods
    ---------------------------------------------------------------------
    pm <- scanHoods(fnc$distance)
    # --- Mergebygroup [] ---
    # Key functions: mergeByGroup
    ---------------------------------------------------------------------
    hoods <- mergeByGroup(pm, fnc$cells)
    # --- Mergehoodspe [] ---
    # Key functions: mergeHoodSpe
    ---------------------------------------------------------------------
    spe <- mergeHoodSpe(spe, hoods)
    # --- Calcmetrics [] ---
    # Key functions: calcMetrics
    ---------------------------------------------------------------------
    spe <- calcMetrics(spe, pm_cols = colnames(hoods))
    # --- Clustbyhood [] ---
    # Key functions: clustByHood
    ---------------------------------------------------------------------
    spe <- clustByHood(spe, pm_cols = colnames(hoods), k = 10)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hoodscanr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hoodscanr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hoodscanr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HOODSCANR:", paste0("    hoodscanr: ", packageVersion("hoodscanR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hoodscanr_results.csv
    touch ${prefix}_hoodscanr_output.rds
    echo "BIOC_HOODSCANR:" > versions.yml
    echo "    hoodscanr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HOODSCANR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HOODSCANR(ch_input)

    emit:
    results  = BIOC_HOODSCANR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HOODSCANR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HOODSCANR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HOODSCANR.out.versions  // channel: path(versions.yml)
}
