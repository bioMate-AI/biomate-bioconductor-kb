#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epivizr
// This package provides connections to the epiviz web app (http://epiviz.cbcb.umd.edu) for interactive
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epivizr/inst/doc/IntroToEpivizr.R
// Upstream  : SummarizedExperiment, antiProfilesData
// Downstream: epivizrStandalone, scTreeViz
//
// Install: BiocManager::install("epivizr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIVIZR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epivizr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epivizr:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epivizr:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epivizr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epivizr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epivizr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epivizr)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(tcga_colon_blocks)
    data(tcga_colon_curves)
    data(apColonData)
    # --- Show [] ---
    # Key functions: show
    ---------------------------------------------------------------------
    show(tcga_colon_blocks)
    # --- List Chart Types [] ---
    # Key functions: list_chart_types
    ---------------------------------------------------------------------
    app$chart_mgr$list_chart_types()
    # --- Print Chart Type Info [] ---
    # Key functions: print_chart_type_info
    ---------------------------------------------------------------------
    app$chart_mgr$print_chart_type_info("BlocksTrack")
    # --- Print Chart Info [] ---
    # Key functions: print_chart_info
    ---------------------------------------------------------------------
    # to list applied chart settings
    app$chart_mgr$print_chart_info(blocks_chart)
    # --- Pdata [] ---
    # Key functions: pData, split, exprs, rowMeans
    ---------------------------------------------------------------------
    keep <- pData(apColonData)$SubType!="adenoma"
    apColonData <- apColonData[,keep]
    status <- pData(apColonData)$Status
    Indexes <- split(seq(along=status),status)
    # --- Data [] ---
    # Key functions: show
    ---------------------------------------------------------------------
    data(tcga_colon_expression)
    show(tcga_colon_expression)
    # --- Stop App [] ---
    # Key functions: stop_app
    ---------------------------------------------------------------------
    app$stop_app()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epivizr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epivizr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epivizr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIVIZR:", paste0("    epivizr: ", packageVersion("epivizr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epivizr_results.csv
    touch ${prefix}_epivizr_output.rds
    echo "BIOC_EPIVIZR:" > versions.yml
    echo "    epivizr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIVIZR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIVIZR(ch_input)

    emit:
    results  = BIOC_EPIVIZR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIVIZR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIVIZR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIVIZR.out.versions  // channel: path(versions.yml)
}
