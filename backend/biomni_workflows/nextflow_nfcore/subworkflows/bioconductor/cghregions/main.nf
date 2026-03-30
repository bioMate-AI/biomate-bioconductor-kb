#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CGHregions
// Dimension Reduction for Array CGH Data with Minimal Information Loss
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CGHregions/inst/doc/CGHregions.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CGHregions")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CGHREGIONS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cghregions"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cghregions:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cghregions:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cghregions_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cghregions_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cghregions_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CGHregions)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(CGHregions)
    data(WiltingCalled)
    WiltingCalled
    # --- Cghregions [] ---
    # Key functions: CGHregions
    regions <- CGHregions(WiltingCalled, averror=0.01)
    regions

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cghregions_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cghregions_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cghregions_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CGHREGIONS:", paste0("    cghregions: ", packageVersion("CGHregions"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cghregions_results.csv
    touch ${prefix}_cghregions_output.rds
    echo "BIOC_CGHREGIONS:" > versions.yml
    echo "    cghregions: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CGHREGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CGHREGIONS(ch_input)

    emit:
    results  = BIOC_CGHREGIONS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CGHREGIONS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CGHREGIONS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CGHREGIONS.out.versions  // channel: path(versions.yml)
}
