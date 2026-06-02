#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSstatsPTM
// MSstatsPTM provides general statistical methods for quantitative characterization of post-translatio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSstatsPTM/inst/doc/MSstatsPTM_LabelFree_Workflow.R
// Upstream  : MSstats
// Downstream: none
//
// Install: BiocManager::install("MSstatsPTM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSSTATSPTM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msstatsptm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msstatsptm:2.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-msstatsptm:2.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msstatsptm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msstatsptm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msstatsptm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSstatsPTM)
    library(jsonlite)

    # --- Data Summarization [] ---
    # Key functions: dataSummarizationPTM
    MSstatsPTM.summary <- dataSummarizationPTM(
        raw.input = msstats_format_tmt,
        verbose = FALSE,
        use_log_file = FALSE,
        append = FALSE
    )


    # --- Quality Control Visualization [] ---
    # Key functions: dataProcessPlotsPTM
    dataProcessPlotsPTM(
        data = MSstatsPTM.summary,
        type = "QCPLOT",
        which.PTM = "allonly",
        address = FALSE
    )
    dataProcessPlotsPTM(
        data = MSstatsPTM.summary,
        type = "ProfilePlot",
        which.Protein = "Q9Y6C9",
        address = FALSE
    )


    # --- Differential Abundance Analysis [] ---
    # Key functions: groupComparisonPTM
    comparison <- matrix(c(-1, 0, 1, 0), nrow = 1)
    row.names(comparison) <- "CCCP-Ctrl"
    colnames(comparison) <- c("CCCP", "Combo", "Ctrl", "USP30_OE")
    MSstatsPTM.model <- groupComparisonPTM(
        data = MSstatsPTM.summary,
        data.type = "LabelFree",
        contrast.matrix = comparison,
        use_log_file = FALSE,
        append = FALSE,
        verbose = FALSE
    )


    # --- Result Visualization [] ---
    # Key functions: groupComparisonPlotsPTM
    groupComparisonPlotsPTM(
        data = MSstatsPTM.model,
        type = "VolcanoPlot",
        FCcutoff = 2,
        logBase.pvalue = 2,
        address = FALSE
    )
    groupComparisonPlotsPTM(
        data = MSstatsPTM.model,
        type = "Heatmap",
        which.PTM = 1:30,
        address = FALSE
    )


    # --- Experimental Design and Sample Size Calculation [] ---
    # Key functions: designSampleSizePTM
    sample_size <- designSampleSizePTM(
        data = MSstatsPTM.model,
        desiredFC = c(2.0, 2.75),
        FDR = 0.05,
        numSample = TRUE,
        power = 0.8
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msstatsptm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msstatsptm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msstatsptm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSSTATSPTM:", paste0("    msstatsptm: ", packageVersion("MSstatsPTM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msstatsptm_results.csv
    touch ${prefix}_msstatsptm_output.rds
    echo "BIOC_MSSTATSPTM:" > versions.yml
    echo "    msstatsptm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSSTATSPTM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSSTATSPTM(ch_input)

    emit:
    results  = BIOC_MSSTATSPTM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSSTATSPTM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSSTATSPTM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSSTATSPTM.out.versions  // channel: path(versions.yml)
}
