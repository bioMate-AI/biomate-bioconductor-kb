#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowStats
// Methods and functionality to analyse flow data that is beyond the basic infrastructure provided by t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowStats/inst/doc/GettingStartedWithFlowStats.R
// Upstream  : flowCore, flowWorkspace, ggcyto, ggridges, gridExtra
// Downstream: flowVS, highthroughputassays
//
// Install: BiocManager::install("flowStats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWSTATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowstats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowstats:4.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowstats:4.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowstats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowstats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowstats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowStats)
    library(GatingSet)
    library(Subset)
    library(jsonlite)

    # --- Quadrant Gating and Normalization [] ---
    # Key functions: quadrantGate, normalize
    tcells_data <- flowWorkspace::gs_pop_get_data(gs, "TCells")
    qgate <- quadrantGate(
        tcells_data,
        stains = c("CD4", "CD8"),
        filterId = "CD4CD8",
        sd = 3
    )
    flowWorkspace::gs_pop_add(gs, qgate, parent = "TCells")
    flowWorkspace::recompute(gs)
    gs <- normalize(
        gs,
        populations = c("CD4+CD8+", "CD4+CD8-", "CD4-CD8+", "CD4-CD8-"),
        dims = c("CD4", "CD8"),
        minCountThreshold = 50
    )


    # --- Range Gating [] ---
    # Key functions: rangeGate
    CD69rg <- rangeGate(
        flowWorkspace::gs_cyto_data(gs),
        stain = "CD69",
        alpha = 0.75,
        filterId = "CD4+CD8-CD69",
        sd = 2.5
    )
    flowWorkspace::gs_pop_add(gs, CD69rg, parent = "CD4+CD8-")
    flowWorkspace::recompute(gs)


    # --- Binning and Chi-Square Statistics [] ---
    # Key functions: proBin, binByRef, calcPearsonChi
    dat <- flowWorkspace::gs_cyto_data(gs)
    datComb <- as(dat, "flowFrame")
    subCount <- nrow(flowCore::exprs(datComb)) / length(dat)
    sf <- flowCore::sampleFilter(filterId = "mySampleFilter", size = subCount)
    fres <- flowCore::filter(datComb, sf)
    ctrlData <- flowCore::Subset(datComb, fres)
    ctrlData <- ctrlData[, -ncol(ctrlData)]
    refBins <- proBin(ctrlData, subCount * 0.05, channels = c("CD4", "CD8"))
    sampBins <- flowCore::fsApply(dat, function(x) {
        binByRef(refBins, x)
    })
    pearsonStat <- lapply(sampBins, function(x) {
        calcPearsonChi(refBins, x)
    })

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowstats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowstats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowstats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWSTATS:", paste0("    flowstats: ", packageVersion("flowStats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowstats_results.csv
    touch ${prefix}_flowstats_output.rds
    echo "BIOC_FLOWSTATS:" > versions.yml
    echo "    flowstats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWSTATS(ch_input)

    emit:
    results  = BIOC_FLOWSTATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWSTATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWSTATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWSTATS.out.versions  // channel: path(versions.yml)
}
