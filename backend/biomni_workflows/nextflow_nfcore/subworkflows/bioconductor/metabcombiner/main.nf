#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metabCombiner
// This package aligns LC-HRMS metabolomics datasets acquired from biologically similar specimens analy
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metabCombiner/inst/doc/metabCombiner_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("metabCombiner")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METABCOMBINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metabcombiner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metabcombiner:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metabcombiner:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metabcombiner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metabcombiner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metabcombiner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metabCombiner)
    library(jsonlite)

    # --- Head [] ---
    # Key functions: files
    ---------------------------------------------------------------------
    head(list.files())
    # --- Metabdata [] ---
    # Key functions: metabData
    ---------------------------------------------------------------------
    p20 <- metabData(table = plasma20, mz = "mz", rt = "rt", id = "identity", adduct = "adduct", samples = "CHEAR", extra = c("Red", "POOL"), rtmin = "min", rtmax = 17.25, measure = "median", zero = FALSE, duplicate = c(0.0025, 0.05))
    # --- Metabdata [] ---
    # Key functions: metabData, getSamples, getExtra, getStats
    ---------------------------------------------------------------------
    p30 <- metabData(table = plasma30, samples = "Red", extra = c("CHEAR", "POOL", "Blank"))
    getSamples(p30) ##should print out red cross sample names
    getExtra(p30) ##should print out extra sample names
    getStats(p30) ##prints a list of dataset statistics
    # --- Metabcombiner [] ---
    # Key functions: metabCombiner
    ---------------------------------------------------------------------
    p.combined = metabCombiner(xdata = p30, ydata = p20, binGap = 0.0075)
    # --- Combinedtable [] ---
    # Key functions: combinedTable
    ---------------------------------------------------------------------
    p.results = combinedTable(p.combined)
    names(p.results)[1:15]
    # --- Calcscores [] ---
    # Key functions: calcScores
    ---------------------------------------------------------------------
    p.combined.4 = calcScores(p.combined.3, A = 70, B = 15, C = 0.5, usePPM = FALSE, useAdduct = FALSE, groups = NULL)
    # --- Evaluateparams [] ---
    # Key functions: evaluateParams
    ---------------------------------------------------------------------
    scores = evaluateParams(p.combined.3, A = seq(50, 120, 10), B = 5:15, C = seq(0,1,0.1), usePPM = FALSE, minScore = 0.5, penalty = 10)
    head(scores)
    # --- Combinedtable [] ---
    # Key functions: combinedTable, labelRows
    ---------------------------------------------------------------------
    combined.table = combinedTable(p.combined.4)
    ##version 1: score-based conflict detection
    combined.table.2 = labelRows(combined.table, minScore = 0.5, maxRankX = 3, maxRankY = 3, method = "score", delta = 0.2, remove = FALSE, balanced = TRUE)
    ##version 2: mzrt-based conflict detection

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metabcombiner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metabcombiner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metabcombiner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METABCOMBINER:", paste0("    metabcombiner: ", packageVersion("metabCombiner"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabcombiner_results.csv
    touch ${prefix}_metabcombiner_output.rds
    echo "BIOC_METABCOMBINER:" > versions.yml
    echo "    metabcombiner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METABCOMBINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METABCOMBINER(ch_input)

    emit:
    results  = BIOC_METABCOMBINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METABCOMBINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METABCOMBINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METABCOMBINER.out.versions  // channel: path(versions.yml)
}
