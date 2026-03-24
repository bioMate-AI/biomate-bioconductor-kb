#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IsoBayes
// IsoBayes is a Bayesian method to perform inference on single protein isoforms. Our approach infers t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IsoBayes/inst/doc/IsoBayes.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("IsoBayes")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOBAYES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isobayes"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isobayes:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isobayes:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isobayes_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isobayes_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isobayes_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IsoBayes)
    library(jsonlite)

    # --- plot_relative_abundances [] ---
    # Key functions: plot_relative_abundances
    plot_relative_abundances(results_normalized, gene_id = "TUBB")
    # --- plotting results no normalization [] ---
    # Key functions: plot_relative_abundances
    plot_relative_abundances(results_normalized, gene_id = "TUBB", normalize_gene = FALSE)
    # --- plot_traceplot [] ---
    # Key functions: plot_traceplot
    plot_traceplot(results_normalized, "TUBB-205")
    plot_traceplot(results_normalized, "TUBB-206")
    plot_traceplot(results_normalized, "TUBB-208")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isobayes_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isobayes_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isobayes_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISOBAYES:", paste0("    isobayes: ", packageVersion("IsoBayes"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isobayes_results.csv
    touch ${prefix}_isobayes_output.rds
    echo "BIOC_ISOBAYES:" > versions.yml
    echo "    isobayes: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISOBAYES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISOBAYES(ch_input)

    emit:
    results  = BIOC_ISOBAYES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISOBAYES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISOBAYES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISOBAYES.out.versions  // channel: path(versions.yml)
}
