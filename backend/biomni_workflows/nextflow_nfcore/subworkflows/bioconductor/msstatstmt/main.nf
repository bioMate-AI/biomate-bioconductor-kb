#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSstatsTMT
// The package provides statistical tools for detecting differentially abundant proteins in shotgun mas
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSstatsTMT/inst/doc/MSstatsTMT.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MSstatsTMT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSSTATSTMT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msstatstmt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msstatstmt:2.14.2--r44_0' :
        'quay.io/biocontainers/bioconductor-msstatstmt:2.14.2--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_msstatstmt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msstatstmt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msstatstmt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSstatsTMT)
    library(MaxQtoMSstatsTMTFormat)
    library(OpenMStoMSstatsTMTFormat)
    library(PDtoMSstatsTMTFormat)
    library(SpectroMinetoMSstatsTMTFormat)
    library(jsonlite)

    # --- Protein Summarization [] ---
    # Key functions: proteinSummarization
    quant_msstats <- proteinSummarization(
        input_pd,
        method = "msstats",
        global_norm = TRUE,
        reference_norm = TRUE,
        remove_norm_channel = TRUE,
        remove_empty_channel = TRUE
    )


    # --- Quality Control Visualization [] ---
    # Key functions: dataProcessPlotsTMT
    dataProcessPlotsTMT(
        data = quant_msstats,
        type = "ProfilePlot",
        width = 21,
        height = 7
    )
    dataProcessPlotsTMT(
        data = quant_msstats,
        type = "QCPlot",
        width = 21,
        height = 7
    )


    # --- Differential Abundance Analysis [] ---
    # Key functions: groupComparisonTMT
    comparison_matrix <- matrix(c(-1, 0, 0, 1), nrow = 1)
    row.names(comparison_matrix) <- "1-0.125"
    colnames(comparison_matrix) <- c("0.125", "0.5", "0.667", "1")
    test_contrast <- groupComparisonTMT(
        data = quant_msstats,
        contrast.matrix = comparison_matrix,
        moderated = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msstatstmt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msstatstmt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msstatstmt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSSTATSTMT:", paste0("    msstatstmt: ", packageVersion("MSstatsTMT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msstatstmt_results.csv
    touch ${prefix}_msstatstmt_output.rds
    echo "BIOC_MSSTATSTMT:" > versions.yml
    echo "    msstatstmt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSSTATSTMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_MSSTATSTMT(ch_input)

    emit:
    results  = BIOC_MSSTATSTMT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSSTATSTMT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSSTATSTMT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSSTATSTMT.out.versions  // channel: path(versions.yml)
}
