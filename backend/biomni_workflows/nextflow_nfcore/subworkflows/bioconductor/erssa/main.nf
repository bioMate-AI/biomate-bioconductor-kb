#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ERSSA
// The ERSSA package takes user supplied RNA-seq differential expression dataset and calculates the num
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ERSSA/inst/doc/ERSSA.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("ERSSA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ERSSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-erssa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-erssa:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-erssa:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_erssa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_erssa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_erssa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ERSSA)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(ERSSA)
    # GTEx dataset with 10 heart and 10 muscle samples
    # "full"" dataset contains all ensembl genes
    data(condition_table.full)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_erssa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_erssa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_erssa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ERSSA:", paste0("    erssa: ", packageVersion("ERSSA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_erssa_results.csv
    touch ${prefix}_erssa_output.rds
    echo "BIOC_ERSSA:" > versions.yml
    echo "    erssa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ERSSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ERSSA(ch_input)

    emit:
    results  = BIOC_ERSSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ERSSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ERSSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ERSSA.out.versions  // channel: path(versions.yml)
}
