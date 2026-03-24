#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iCOBRA
// This package provides functions for calculation and visualization of performance metrics for evaluat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iCOBRA/inst/doc/iCOBRA.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("iCOBRA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICOBRA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-icobra"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-icobra:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-icobra:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_icobra_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_icobra_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_icobra_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(COBRAData_from_text)
    library(COBRAData_to_text)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, class
    -----------------------------------------------------------------------------------------
    library(iCOBRA)
    data(cobradata_example)
    class(cobradata_example)
    cobradata_example
    # --- Calculate Adjp [] ---
    # Key functions: calculate_adjp
    -----------------------------------------------------------------------------------------
    cobradata_example <- calculate_adjp(cobradata_example)
    # --- Calculate Performance [] ---
    # Key functions: calculate_performance, slotNames
    -----------------------------------------------------------------------------------------
    cobraperf <- calculate_performance(cobradata_example, binary_truth = "status",
                                      cont_truth = "logFC", splv = "none",
                                      maxsplit = 4)
    slotNames(cobraperf)
    # --- Prepare Data For Plot [] ---
    # Key functions: prepare_data_for_plot
    -----------------------------------------------------------------------------------------
    cobraplot <- prepare_data_for_plot(cobraperf, colorscheme = "Dark2",
                                      facetted = TRUE)
    # --- Cobradata To Text [] ---
    # Key functions: COBRAData_to_text
    -----------------------------------------------------------------------------------------
    COBRAData_to_text(cobradata = cobradata_example,
                      truth_file = "cobradata_truth.txt",
                      result_files = "cobradata_results.txt",
                      feature_id = "feature")
    # --- Cobradata From Text [] ---
    # Key functions: COBRAData_from_text
    -----------------------------------------------------------------------------------------
    cobra <- COBRAData_from_text(truth_file = "cobradata_truth.txt",
                                 result_files = "cobradata_results.txt",
                                 feature_id = "feature")
    cobra

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_icobra_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_icobra_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_icobra_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ICOBRA:", paste0("    icobra: ", packageVersion("iCOBRA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_icobra_results.csv
    touch ${prefix}_icobra_output.rds
    echo "BIOC_ICOBRA:" > versions.yml
    echo "    icobra: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ICOBRA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ICOBRA(ch_input)

    emit:
    results  = BIOC_ICOBRA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ICOBRA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ICOBRA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ICOBRA.out.versions  // channel: path(versions.yml)
}
