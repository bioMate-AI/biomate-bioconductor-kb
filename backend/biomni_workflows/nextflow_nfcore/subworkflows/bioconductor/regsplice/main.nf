#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regsplice
// Statistical methods for detection of differential splicing (differential exon usage) in RNA-seq and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regsplice/inst/doc/regsplice-workflow.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("regsplice")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGSPLICE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regsplice"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regsplice:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regsplice:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regsplice_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regsplice_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regsplice_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LRTests)
    library(RegspliceData)
    library(jsonlite)

    # --- Regsplicedata [] ---
    # Key functions: RegspliceData, regsplice
    ---------------------------------------------------------------------
    library(regsplice)
    rs_data <- RegspliceData(counts, gene_IDs, n_exons, condition)
    rs_results <- suppressWarnings(regsplice(rs_data, seed = 123))
    # --- Summarytable [] ---
    # Key functions: summaryTable
    ---------------------------------------------------------------------
    summaryTable(rs_results)
    # --- Regsplicedata [] ---
    # Key functions: RegspliceData
    ---------------------------------------------------------------------
    library(regsplice)
    rs_data <- RegspliceData(counts, gene_IDs, n_exons, condition)
    # --- Filterzeros [] ---
    # Key functions: filterZeros
    ---------------------------------------------------------------------
    rs_data <- filterZeros(rs_data)
    # --- Filterlowcounts [] ---
    # Key functions: filterLowCounts
    ---------------------------------------------------------------------
    rs_data <- filterLowCounts(rs_data)
    # --- Runnormalization [] ---
    # Key functions: runNormalization
    ---------------------------------------------------------------------
    rs_data <- runNormalization(rs_data)
    # --- Runvoom [] ---
    # Key functions: runVoom, colData
    ---------------------------------------------------------------------
    rs_data <- runVoom(rs_data)
    # view column meta-data including normalization factors and normalized library sizes
    colData(rs_data)
    # --- Initializeresults [] ---
    # Key functions: initializeResults
    ---------------------------------------------------------------------
    rs_results <- initializeResults(rs_data)
    # --- Suppresswarnings [] ---
    # Key functions: fitRegMultiple, fitNullMultiple, models, fitFullMultiple
    ---------------------------------------------------------------------
    # set random seed for reproducibility
    seed <- 123
    # fit regularized models
    rs_results <- suppressWarnings(fitRegMultiple(rs_results, rs_data, seed = seed))
    # --- Lrtests [] ---
    # Key functions: LRTests
    ---------------------------------------------------------------------
    rs_results <- LRTests(rs_results)
    # --- Summarytable [] ---
    # Key functions: summaryTable
    ---------------------------------------------------------------------
    summaryTable(rs_results)
    # --- Sum [] ---
    # Key functions: p_adj
    ---------------------------------------------------------------------
    sum(p_adj(rs_results) < 0.05)
    table(p_adj(rs_results) < 0.05)
    # --- Createdesignmatrix [] ---
    # Key functions: createDesignMatrix
    ---------------------------------------------------------------------
    # gene with 3 exons
    # 4 biological samples; 2 samples in each of 2 conditions
    design_example <- createDesignMatrix(condition = rep(c(0, 1), each = 2), n_exons = 3)
    design_example

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regsplice_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regsplice_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regsplice_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGSPLICE:", paste0("    regsplice: ", packageVersion("regsplice"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regsplice_results.csv
    touch ${prefix}_regsplice_output.rds
    echo "BIOC_REGSPLICE:" > versions.yml
    echo "    regsplice: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGSPLICE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGSPLICE(ch_input)

    emit:
    results  = BIOC_REGSPLICE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGSPLICE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGSPLICE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGSPLICE.out.versions  // channel: path(versions.yml)
}
