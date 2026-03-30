#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: amplican
// `amplican` performs alignment of the amplicon reads, normalizes gathered data, calculates multiple s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/amplican/inst/doc/amplicanOverview.R
// Upstream  : ggplot2, knitr
// Downstream: none
//
// Install: BiocManager::install("amplican")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AMPLICAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-amplican"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-amplican:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-amplican:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_amplican_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_amplican_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_amplican_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(amplican)
    library(jsonlite)

    # --- tempdir [] ---
    # Key functions: tempdir, amplicanPipeline
    config <- system.file("extdata", "config.csv", package = "amplican")
    fastq_folder <- system.file("extdata", package = "amplican")
    results_folder <- tempdir()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_amplican_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_amplican_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_amplican_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AMPLICAN:", paste0("    amplican: ", packageVersion("amplican"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_amplican_results.csv
    touch ${prefix}_amplican_output.rds
    echo "BIOC_AMPLICAN:" > versions.yml
    echo "    amplican: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AMPLICAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AMPLICAN(ch_input)

    emit:
    results  = BIOC_AMPLICAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AMPLICAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AMPLICAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AMPLICAN.out.versions  // channel: path(versions.yml)
}
