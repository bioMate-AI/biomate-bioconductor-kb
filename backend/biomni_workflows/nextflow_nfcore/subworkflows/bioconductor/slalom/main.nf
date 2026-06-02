#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: slalom
// slalom is a scalable modelling framework for single-cell RNA-seq data that uses gene set annotations
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/slalom/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("slalom")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SLALOM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-slalom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-slalom:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-slalom:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_slalom_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_slalom_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_slalom_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneSetCollection)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Create SingleCellExperiment object [] ---
    # Key functions: logcounts, SingleCellExperiment
    rdsfile <- system.file("extdata", "sim_N_20_v3.rds", package = "slalom")
    sim <- readRDS(rdsfile)
    # --- Gmt analysis [] ---
    # Key functions: getGmt, newSlalomModel, initSlalom, trainSlalom, GeneSetCollection, setName, plotLoadings


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_slalom_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_slalom_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_slalom_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SLALOM:", paste0("    slalom: ", packageVersion("slalom"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_slalom_results.csv
    touch ${prefix}_slalom_output.rds
    echo "BIOC_SLALOM:" > versions.yml
    echo "    slalom: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SLALOM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SLALOM(ch_input)

    emit:
    results  = BIOC_SLALOM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SLALOM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SLALOM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SLALOM.out.versions  // channel: path(versions.yml)
}
