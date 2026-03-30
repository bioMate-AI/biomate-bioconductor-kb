#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiContacts
// HiContacts provides a collection of tools to analyse and visualize Hi-C datasets imported in R by Hi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiContacts/inst/doc/HiContacts.R
// Upstream  : GenomicRanges, HiCExperiment, HiContactsData, InteractionSet, dplyr
// Downstream: none
//
// Install: BiocManager::install("HiContacts")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICONTACTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicontacts"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicontacts:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicontacts:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicontacts_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicontacts_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicontacts_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(HiContactsData)
    library(P)
    library(SerialParam)
    library(jsonlite)

    # --- Hicontactsdata [] ---
    # Key functions: HiContactsData, import
    ---------------------------------------------------------------------
    library(dplyr)
    library(ggplot2)
    library(HiCExperiment)
    library(HiContacts)
    # --- Plotmatrix [] ---
    # Key functions: plotMatrix, refocus
    ---------------------------------------------------------------------
    ## Square matrix
    plotMatrix(hic, use.scores = 'balanced', limits = c(-4, -1))
    ## Horizontal matrix
    plotMatrix(
    # --- Hicontactsdata [] ---
    # Key functions: HiContactsData, import, makeGInteractionsFromGRangesPairs, plotMatrix
    ---------------------------------------------------------------------
    mcool_file <- HiContactsData('yeast_wt', format = 'mcool')
    loops <- system.file("extdata", 'S288C-loops.bedpe', package = 'HiCExperiment') |>
        import() |>
        makeGInteractionsFromGRangesPairs()
    # --- Aggregate [] ---
    # Key functions: aggregate, SerialParam, plotMatrix, bgrColors
    ---------------------------------------------------------------------
    aggr_centros <- HiContacts::aggregate(
        hic, targets = loops, BPPARAM = BiocParallel::SerialParam()
    )
    plotMatrix(
    # --- Hicontactsdata [] ---
    # Key functions: HiContactsData, import, autocorrelate, scores, plotMatrix
    ---------------------------------------------------------------------
    mcool_file <- HiContactsData('mESCs', format = 'mcool')
    hic <- import(mcool_file, format = 'mcool', focus = 'chr2', resolution = 160000)
    hic <- autocorrelate(hic)
    scores(hic)
    # --- Import [] ---
    # Key functions: import, detrend, wrap_plots, plotMatrix
    ---------------------------------------------------------------------
    hic <- import(mcool_file, format = 'mcool', focus = 'chr18:20000000-35000000', resolution = 40000)
    detrended_hic <- detrend(hic)
    patchwork::wrap_plots(
        plotMatrix(detrended_hic, use.scores = 'expected', scale = 'log10', limits = c(-3, -1), dpi = 120),
    # --- Hicontactsdata [] ---
    # Key functions: HiContactsData, import
    ---------------------------------------------------------------------
    mcool_file_1 <- HiContactsData('yeast_eco1', format = 'mcool')
    mcool_file_2 <- HiContactsData('yeast_wt', format = 'mcool')
    hic_1 <- import(mcool_file_1, format = 'mcool', focus = 'II:1-300000', resolution = 2000)
    hic_2 <- import(mcool_file_2, format = 'mcool', focus = 'II:1-300000', resolution = 2000)
    # --- Import [] ---
    # Key functions: import, divide, wrap_plots, plotMatrix, bwrColors
    ---------------------------------------------------------------------
    hic_1 <- import(mcool_file_1, format = 'mcool', focus = 'II', resolution = 2000)
    hic_2 <- import(mcool_file_2, format = 'mcool', focus = 'II', resolution = 2000)
    div_hic <- divide(hic_1, by = hic_2)
    div_hic
    # --- Despeckle [] ---
    # Key functions: despeckle, wrap_plots, plotMatrix
    ---------------------------------------------------------------------
    hic_1_despeckled <- despeckle(hic_1)
    hic_1_despeckled5 <- despeckle(hic_1, focal.size = 5)
    p <- patchwork::wrap_plots(
        plotMatrix(hic_1, use.scores = 'balanced', scale = 'log10', limits = c(-4, -1)),
    # --- Hicontactsdata [] ---
    # Key functions: HiContactsData, import, getCompartments, export, coverage, metadata, topologicalFeatures
    ---------------------------------------------------------------------
    mcool_file <- HiContactsData('yeast_wt', format = 'mcool')
    hic <- import(mcool_file, format = 'mcool', resolution = 16000)
    # - Get compartments
    hic <- getCompartments(hic, chromosomes = c('XV', 'XVI'))
    # --- Refocus [] ---
    # Key functions: refocus, zoom, getDiamondInsulation, getBorders, export, coverage, metadata, topologicalFeatures
    ---------------------------------------------------------------------
    # - Compute insulation score
    hic <- refocus(hic, 'II:1-300000') |>
        zoom(resolution = 1000) |>
        getDiamondInsulation(window_size = 8000) |>
    # --- Hicontactsdata [] ---
    # Key functions: HiContactsData, import, virtual4C, GRanges, plot4C, aes
    ---------------------------------------------------------------------
    mcool_file <- HiContactsData('mESCs', format = 'mcool')
    hic <- import(mcool_file, format = 'mcool', focus = 'chr18:20000000-35000000', resolution = 40000)
    v4C <- virtual4C(hic, viewpoint = GRanges('chr18:31000000-31050000'))
    plot4C(v4C, ggplot2::aes(x = center, y = score))
    # --- Hicontactsdata [] ---
    # Key functions: HiContactsData, import, cisTransRatio
    ---------------------------------------------------------------------
    mcool_file <- HiContactsData('yeast_wt', format = 'mcool')
    hic <- import(mcool_file, format = 'mcool', resolution = 1000)
    cisTransRatio(hic)
    # --- Hicontactsdata [] ---
    # Key functions: HiContactsData, import, distanceLaw, plotPs, aes, pairsFile, plotPsSlope, P
    ---------------------------------------------------------------------
    # Without a pairs file
    mcool_file <- HiContactsData('yeast_wt', format = 'mcool')
    hic <- import(mcool_file, format = 'mcool', resolution = 1000)
    ps <- distanceLaw(hic)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicontacts_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicontacts_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicontacts_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICONTACTS:", paste0("    hicontacts: ", packageVersion("HiContacts"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicontacts_results.csv
    touch ${prefix}_hicontacts_output.rds
    echo "BIOC_HICONTACTS:" > versions.yml
    echo "    hicontacts: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICONTACTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICONTACTS(ch_input)

    emit:
    results  = BIOC_HICONTACTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICONTACTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICONTACTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICONTACTS.out.versions  // channel: path(versions.yml)
}
