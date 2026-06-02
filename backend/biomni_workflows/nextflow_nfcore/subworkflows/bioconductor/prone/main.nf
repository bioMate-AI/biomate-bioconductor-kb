#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PRONE
// High-throughput omics data are often affected by systematic biases introduced throughout all the ste
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PRONE/inst/doc/Differential_Expression.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PRONE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PRONE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-prone"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-prone:1.0.7--r44_0' :
        'quay.io/biocontainers/bioconductor-prone:1.0.7--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_prone_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_prone_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_prone_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PRONE)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>", message = TRUE, warning = FALSE,
      fig.width=8,
      fig.height =6
    )

    # --- Load Real Tmt [] ---
    # Key functions: normalize_se, remove_reference_samples, specify_comparisons, tuberculosis_TMT_se, IRS_on_RobNorm, IRS_on_Median, IRS_on_LoessF, IRS_on_Quantile
    data("tuberculosis_TMT_se")
    se <- tuberculosis_TMT_se

    ## -----------------------------------------------------------------------------
    se_norm <- normalize_se(se, c("IRS_on_RobNorm", "IRS_on_Median", 
                                  "IRS_on_LoessF", "IRS_on_Quantile"), 
                            combination_pattern = "_on_")

    ## -----------------------------------------------------------------------------
    se_norm <- remove_reference_samples(se_norm)

    ## -----------------------------------------------------------------------------
    comparisons <- specify_comparisons(se_norm, condition = "Group", 
                                       sep = NULL, control = NULL)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_prone_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_prone_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_prone_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PRONE:", paste0("    prone: ", packageVersion("PRONE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prone_results.csv
    touch ${prefix}_prone_output.rds
    echo "BIOC_PRONE:" > versions.yml
    echo "    prone: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PRONE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PRONE(ch_input)

    emit:
    results  = BIOC_PRONE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PRONE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PRONE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PRONE.out.versions  // channel: path(versions.yml)
}
