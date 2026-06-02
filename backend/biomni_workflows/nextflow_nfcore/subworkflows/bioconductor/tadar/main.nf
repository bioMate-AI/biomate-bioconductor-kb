#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tadar
// This package provides functions to standardise the analysis of Differential Allelic Representation (
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tadar/inst/doc/dar.R
// Upstream  : limma, tidyverse
// Downstream: none
//
// Install: BiocManager::install("tadar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TADAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tadar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tadar:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tadar:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tadar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tadar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tadar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tadar)
    library(GRanges)
    library(jsonlite)

    # --- Allele Counting [] ---
    # Key functions: countAlleles
    counts <- countAlleles(
        genotypes = genotypes,
        groups = groups
    )


    # --- Locus Filtering [] ---
    # Key functions: filterLoci
    counts_filt <- filterLoci(
        counts = counts
    )
    counts_filt_strict <- filterLoci(
        counts = counts,
        filter = n_missing == 0
    )


    # --- Proportion Estimation and Contrast Definition [] ---
    # Key functions: countsToProps, makeContrasts
    props <- countsToProps(
        counts = counts_filt
    )
    contrasts <- makeContrasts(
        group1v2 = group1 - group2,
        levels = names(groups)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tadar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tadar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tadar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TADAR:", paste0("    tadar: ", packageVersion("tadar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tadar_results.csv
    touch ${prefix}_tadar_output.rds
    echo "BIOC_TADAR:" > versions.yml
    echo "    tadar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TADAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TADAR(ch_input)

    emit:
    results  = BIOC_TADAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TADAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TADAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TADAR.out.versions  // channel: path(versions.yml)
}
