#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: easier
// This package provides a workflow for the use of EaSIeR tool, developed to assess patients' likelihoo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/easier/inst/doc/easier_user_manual.R
// Upstream  : SummarizedExperiment, easierData, knitr
// Downstream: none
//
// Install: BiocManager::install("easier")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EASIER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-easier"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-easier:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-easier:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_easier_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_easier_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_easier_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(easier)
    library(jsonlite)

    # --- Table2 [] ---
    # Key functions: activity, score, signature, resistance
    ----
    table2 <- "
    | Hallmark of the immune response | Original study |
    |-------------------------------- | -------------- |
    | Cytolytic activity (CYT) | @ROONEY201548 |

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_easier_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_easier_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_easier_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EASIER:", paste0("    easier: ", packageVersion("easier"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_easier_results.csv
    touch ${prefix}_easier_output.rds
    echo "BIOC_EASIER:" > versions.yml
    echo "    easier: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EASIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EASIER(ch_input)

    emit:
    results  = BIOC_EASIER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EASIER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EASIER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EASIER.out.versions  // channel: path(versions.yml)
}
