#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Summix
// This package contains the Summix2 method for estimating and adjusting for substructure in genetic su
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Summix/inst/doc/Summix.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Summix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SUMMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-summix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-summix:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-summix:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_summix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_summix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_summix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Summix)
    library(jsonlite)

    # --- summix [] ---
    # Key functions: summix
    library(Summix)
    data("ancestryData")
    # --- adjAF example [] ---
    # Key functions: adjAF
    library(Summix)
    data("ancestryData")
    # --- summix local example [] ---
    # Key functions: summix_local
    library(Summix)
    data("ancestryData")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_summix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_summix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_summix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SUMMIX:", paste0("    summix: ", packageVersion("Summix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summix_results.csv
    touch ${prefix}_summix_output.rds
    echo "BIOC_SUMMIX:" > versions.yml
    echo "    summix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SUMMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SUMMIX(ch_input)

    emit:
    results  = BIOC_SUMMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SUMMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SUMMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SUMMIX.out.versions  // channel: path(versions.yml)
}
