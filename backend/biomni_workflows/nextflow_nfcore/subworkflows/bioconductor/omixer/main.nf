#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Omixer
// Omixer - an Bioconductor package for multivariate and reproducible sample randomization, which ensur
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Omixer/inst/doc/omixer-vignette.R
// Upstream  : dplyr, forcats, ggplot2, magick, stringr
// Downstream: none
//
// Install: BiocManager::install("Omixer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMIXER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omixer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omixer:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omixer:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omixer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omixer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omixer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Omixer)
    library(jsonlite)

    # --- rna toy data [] ---
    # Key functions: tibble

    # --- rna omixer rand [] ---
    # Key functions: omixerRand

    # --- omixer specific rna [] ---
    # Key functions: omixerSpecific
    load("randomSeed.Rdata")
    # --- omixer sheet rna [] ---
    # Key functions: omixerSheet
    omixerSheet(omixerLayout)
    # --- dna toy data [] ---
    # Key functions: tibble

    # --- rep [] ---
    # Key functions: rep
    mask <- rep(c(rep(0, 88), rep(1, 8)), 7)
    # --- dna omixer rand [] ---
    # Key functions: omixerRand

    # --- omixer v simple [] ---
    # Key functions: omixerRand

    # --- omixer specific dna [] ---
    # Key functions: omixerSpecific
    load("randomSeed.Rdata")
    # --- omixer Sheet [] ---
    # Key functions: omixerSheet
    omixerSheet(omixerLayout, group="tissue")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omixer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omixer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omixer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMIXER:", paste0("    omixer: ", packageVersion("Omixer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omixer_results.csv
    touch ${prefix}_omixer_output.rds
    echo "BIOC_OMIXER:" > versions.yml
    echo "    omixer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMIXER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMIXER(ch_input)

    emit:
    results  = BIOC_OMIXER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMIXER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMIXER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMIXER.out.versions  // channel: path(versions.yml)
}
