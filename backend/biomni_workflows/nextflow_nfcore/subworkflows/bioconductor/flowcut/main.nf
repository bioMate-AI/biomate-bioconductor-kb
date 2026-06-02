#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowCut
// Common techinical complications such as clogging can result in spurious events and fluorescence inte
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowCut/inst/doc/flowCut.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowCut")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowcut"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowcut:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowcut:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowcut_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowcut_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowcut_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowCut)
    library(jsonlite)

    # --- Quality Control and Outlier Detection ---
    # Key functions: flowCut
    data(flowCutData)
    res_flowCut <- flowCut(
        flowCutData[[1]],
        FileID = 1,
        Plot = "All"
    )

    # --- Stringent Outlier Filtering ---
    # Key functions: flowCut
    data(flowCutData)
    res_flowCut_stringent <- flowCut(
        flowCutData[[2]],
        FileID = 2,
        Plot = "All",
        AllowFlaggedRerun = FALSE,
        MaxValleyHgt = 0.01
    )

    # --- Flagged Rerun Optimization ---
    # Key functions: flowCut
    data(flowCutData)
    res_flowCut_rerun <- flowCut(
        flowCutData[[4]],
        FileID = 8,
        AllowFlaggedRerun = TRUE,
        UseOnlyWorstChannels = TRUE,
        Plot = "All"
    )

    # --- Custom Gate Line Force Filtering ---
    # Key functions: flowCut
    data(flowCutData)
    res_flowCut_gate <- flowCut(
        flowCutData[[3]],
        FileID = 6,
        Plot = "All",
        GateLineForce = 44
    )

    # --- Extraction of Quality Metrics ---
    # Key functions: flowCut
    data(flowCutData)
    res_flowCut_metrics <- flowCut(
        flowCutData[[3]],
        FileID = 4,
        Plot = "None",
        AllowFlaggedRerun = FALSE,
        MaxPercCut = 0.15
    )
    metrics_summary <- res_flowCut_metrics$data
    pct_removed <- metrics_summary["% of events removed", ]


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowcut_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowcut_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowcut_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWCUT:", paste0("    flowcut: ", packageVersion("flowCut"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowcut_results.csv
    touch ${prefix}_flowcut_output.rds
    echo "BIOC_FLOWCUT:" > versions.yml
    echo "    flowcut: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWCUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWCUT(ch_input)

    emit:
    results  = BIOC_FLOWCUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWCUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWCUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWCUT.out.versions  // channel: path(versions.yml)
}
