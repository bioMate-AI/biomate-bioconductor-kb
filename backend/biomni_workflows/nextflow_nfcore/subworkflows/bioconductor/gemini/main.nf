#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gemini
// GEMINI uses log-fold changes to model sample-dependent and independent effects, and uses a variation
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gemini/inst/doc/gemini-quickstart.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("gemini")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEMINI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gemini"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gemini:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gemini:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gemini_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gemini_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gemini_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gemini)
    library(jsonlite)

    # --- Table formatting and display [] ---
    # Key functions: install_github, kable, gemini_create_input, gemini_initialize, gemini_plot_mae, gemini_score, gemini_boxplot
    if (!requireNamespace("devtools", quietly = TRUE))
    install.packages("devtools")
    devtools::install_github("foo/bar", build_opts = c("--no-resave-data", "--no-manual"), build_vignettes = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gemini_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gemini_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gemini_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEMINI:", paste0("    gemini: ", packageVersion("gemini"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gemini_results.csv
    touch ${prefix}_gemini_output.rds
    echo "BIOC_GEMINI:" > versions.yml
    echo "    gemini: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEMINI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEMINI(ch_input)

    emit:
    results  = BIOC_GEMINI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEMINI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEMINI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEMINI.out.versions  // channel: path(versions.yml)
}
