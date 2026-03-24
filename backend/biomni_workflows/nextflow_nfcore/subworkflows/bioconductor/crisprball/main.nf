#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CRISPRball
// A Shiny application for visualization, exploration, comparison, and filtering of CRISPR screens anal
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CRISPRball/inst/doc/CRISPRball.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("CRISPRball")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRBALL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crisprball"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crisprball:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-crisprball:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crisprball_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crisprball_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crisprball_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CRISPRball)
    library(jsonlite)

    # --- Delim [] ---
    # Key functions: delim
    ---------------------------------------------------------------------
    # Create lists of results summaries for each dataset.
    d1.genes <- read.delim(system.file("extdata", "esc1.gene_summary.txt",
        package = "CRISPRball"
    ), check.names = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crisprball_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crisprball_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crisprball_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRISPRBALL:", paste0("    crisprball: ", packageVersion("CRISPRball"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crisprball_results.csv
    touch ${prefix}_crisprball_output.rds
    echo "BIOC_CRISPRBALL:" > versions.yml
    echo "    crisprball: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRISPRBALL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRISPRBALL(ch_input)

    emit:
    results  = BIOC_CRISPRBALL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRISPRBALL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRISPRBALL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRISPRBALL.out.versions  // channel: path(versions.yml)
}
