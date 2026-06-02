#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SUITOR
// An unsupervised cross-validation method to select the optimal number of mutational signatures. A dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SUITOR/inst/doc/vignette.R
// Upstream  : MutationalPatterns
// Downstream: none
//
// Install: BiocManager::install("SUITOR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SUITOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-suitor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-suitor:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-suitor:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_suitor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_suitor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_suitor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SUITOR)
    library(jsonlite)

    # --- suitor [] ---
    # Key functions: suitor
    v1 <- c("min.value", "min.rank", "max.rank", "k.fold", "em.eps", "max.iter",
    v2 <- c("Minimum value of matrix before factorizing", "Minimum rank",
    "0 or 1 to print info (0=no printing)")
    # --- suitor Extract W H [] ---
    # Key functions: suitorExtractWH, get_known_signatures, plot_96_profile
    v1 <- c("min.value", "n.starts", "print")
    v2 <- c("Minimum value of matrix before factorizing",
    "0 or 1 to print info (0=no printing)")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_suitor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_suitor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_suitor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SUITOR:", paste0("    suitor: ", packageVersion("SUITOR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_suitor_results.csv
    touch ${prefix}_suitor_output.rds
    echo "BIOC_SUITOR:" > versions.yml
    echo "    suitor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SUITOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SUITOR(ch_input)

    emit:
    results  = BIOC_SUITOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SUITOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SUITOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SUITOR.out.versions  // channel: path(versions.yml)
}
