#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DifferentialRegulation
// DifferentialRegulation is a method for detecting differentially regulated genes between two groups o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DifferentialRegulation/inst/doc/DifferentialRegulation.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DifferentialRegulation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFERENTIALREGULATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-differentialregulation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-differentialregulation:2.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-differentialregulation:2.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_differentialregulation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_differentialregulation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_differentialregulation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DifferentialRegulation)
    library(jsonlite)

    # --- plot_pi [] ---
    # Key functions: plot_pi
    plot_pi(results,
    plot_pi(results,
    # --- plot pi USA [] ---
    # Key functions: plot_pi
    plot_pi(results,
    plot_pi(results,
    # --- plot_traceplot [] ---
    # Key functions: plot_traceplot
    plot_traceplot(results,
    plot_traceplot(results,
    # --- plot_bulk_pi [] ---
    # Key functions: plot_bulk_pi
    plot_bulk_pi(results,
    plot_bulk_pi(results,
    # --- plot_bulk_traceplot [] ---
    # Key functions: plot_bulk_traceplot
    plot_bulk_traceplot(results,
    plot_bulk_traceplot(results,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_differentialregulation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_differentialregulation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_differentialregulation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIFFERENTIALREGULATION:", paste0("    differentialregulation: ", packageVersion("DifferentialRegulation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differentialregulation_results.csv
    touch ${prefix}_differentialregulation_output.rds
    echo "BIOC_DIFFERENTIALREGULATION:" > versions.yml
    echo "    differentialregulation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIFFERENTIALREGULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIFFERENTIALREGULATION(ch_input)

    emit:
    results  = BIOC_DIFFERENTIALREGULATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIFFERENTIALREGULATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIFFERENTIALREGULATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIFFERENTIALREGULATION.out.versions  // channel: path(versions.yml)
}
