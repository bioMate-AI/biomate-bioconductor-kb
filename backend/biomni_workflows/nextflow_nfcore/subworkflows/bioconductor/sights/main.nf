#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sights
// SIGHTS is a suite of normalization methods, statistical tests, and diagnostic graphical tools for hi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sights/inst/doc/sights.R
// Upstream  : ggthemes, gridExtra, knitr, xlsx
// Downstream: none
//
// Install: BiocManager::install("sights")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGHTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sights"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sights:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sights:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sights_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sights_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sights_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(View)
    library(jsonlite)

    # --- View [] ---
    # Key functions: View, edit
    View(inglese)
    edit(inglese)
    head(inglese)
    # --- args [] ---
    # Key functions: args, example
    ls("package:sights")
    lsf.str("package:sights")
    args(plotSights)
    # --- norm S P A W N [] ---
    # Key functions: normSPAWN, normSights, statRVM, statSights
    library(sights)
    data("inglese")
    spawn_results <- normSPAWN(dataMatrix = inglese, plateRows = 32, plateCols = 40, dataRows = NULL, dataCols = 3:44, trimFactor = 0.2, wellCorrection = TRUE, biasMatrix = NULL, biasCols = 1:18)
    # --- raw bias0 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Box", plotMatrix = inglese, plotCols = 3:5, plotName = "Raw Exp1")
    # --- raw bias1 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Heatmap", plotMatrix = inglese, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 3, plotName = "Raw Exp1")
    sights::plotSights(plotMethod = "3d", plotMatrix = inglese, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 3, plotName = "Raw Exp1")
    sights::plotSights(plotMethod = "Autoco", plotMatrix = inglese, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 3:5, plotSep = FALSE, plotName = "Raw Exp1")
    # --- raw bias2 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Scatter", plotMatrix = inglese, repIndex = c(1,1), plotRows = NULL, plotCols = 3:4, plotName = "Raw Exp1", alpha=0.2)
    # --- z bias0 [] ---
    # Key functions: plotSights
    Z.norm.inglese.01 <- sights::normSights(normMethod = "Z", dataMatrix = inglese, dataRows = NULL, dataCols = 3:5)
    sights::plotSights(plotMethod = "Box", plotMatrix = Z.norm.inglese.01, plotCols = 1:3, plotName = "Z Exp1")
    # --- z bias1 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Heatmap", plotMatrix = Z.norm.inglese.01, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 1, plotName = "Z Exp1")
    sights::plotSights(plotMethod = "3d", plotMatrix = Z.norm.inglese.01, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 1, plotName = "Z Exp1")
    sights::plotSights(plotMethod = "Autoco", plotMatrix = Z.norm.inglese.01, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 1:3, plotSep = FALSE, plotName = "Z Exp1")
    # --- z bias2 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Scatter", plotMatrix = Z.norm.inglese.01, repIndex = c(1,1), plotRows = NULL, plotCols = 1:2, plotName = "Z Exp1", alpha=0.2)
    # --- spawn bias0 [] ---
    # Key functions: plotSights
    SPAWN.norm.inglese.01 <- sights::normSights(normMethod = "SPAWN", dataMatrix = inglese, plateRows = 32, plateCols = 40, dataRows = NULL, dataCols = 3:44, trimFactor = 0.2, wellCorrection = TRUE, biasCols = 1:18)
    sights::plotSights(plotMethod = "Box", plotMatrix = SPAWN.norm.inglese.01, plotCols = 1:3, plotName = "SPAWN Exp1")
    # --- spawn bias1 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Heatmap", plotMatrix = SPAWN.norm.inglese.01, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 1, plotName = "SPAWN Exp1")
    sights::plotSights(plotMethod = "3d", plotMatrix = SPAWN.norm.inglese.01, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 1, plotName = "SPAWN Exp1")
    sights::plotSights(plotMethod = "Autoco", plotMatrix = SPAWN.norm.inglese.01, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 1:3, plotSep = FALSE, plotName = "SPAWN Exp1")
    # --- spawn bias2 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Scatter", plotMatrix = SPAWN.norm.inglese.01, repIndex = c(1,1), plotRows = NULL, plotCols = 1:2, plotName = "SPAWN Exp1", alpha=0.2)
    # --- raw bias9 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Box", plotMatrix = inglese, plotCols = 27:29, plotName = "Raw Exp9")
    # --- raw bias10 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Heatmap", plotMatrix = inglese, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 27, plotName = "Raw Exp9")
    sights::plotSights(plotMethod = "3d", plotMatrix = inglese, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 27, plotName = "Raw Exp9")
    sights::plotSights(plotMethod = "Autoco", plotMatrix = inglese, plateRows = 32, plateCols = 40, plotRows = NULL, plotCols = 27:29, plotSep = FALSE, plotName = "Raw Exp9")
    # --- raw bias11 [] ---
    # Key functions: plotSights
    sights::plotSights(plotMethod = "Scatter", plotMatrix = inglese, repIndex = c(1,1), plotRows = NULL, plotCols = 27:28, plotName = "Raw Exp9", alpha=0.2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sights_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sights_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sights_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGHTS:", paste0("    sights: ", packageVersion("sights"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sights_results.csv
    touch ${prefix}_sights_output.rds
    echo "BIOC_SIGHTS:" > versions.yml
    echo "    sights: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGHTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIGHTS(ch_input)

    emit:
    results  = BIOC_SIGHTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGHTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGHTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGHTS.out.versions  // channel: path(versions.yml)
}
