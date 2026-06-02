#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CTSV
// The R package CTSV implements the CTSV approach developed by Jinge Yu and Xiangyu Luo that detects c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CTSV/inst/doc/CTSV.R
// Upstream  : SpatialExperiment
// Downstream: none
//
// Install: BiocManager::install("CTSV")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CTSV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ctsv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ctsv:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ctsv:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ctsv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ctsv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ctsv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CTSV)
    library(jsonlite)

    # --- "install" [] ---
    # Key functions: valid
    if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager")
    BiocManager::install("CTSV", version = "devel")
    # --- assay [] ---
    # Key functions: assay
    data("CTSVexample_data", package="CTSV")
    Y <- assay(spe)
    dim(Y)
    # --- Run CTSV [] ---
    # Key functions: CTSV
    result <- CTSV(spe,W,num_core = 8)
    # --- sv Gene [] ---
    # Key functions: svGene
    re <- svGene(result$qval,0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ctsv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ctsv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ctsv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CTSV:", paste0("    ctsv: ", packageVersion("CTSV"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ctsv_results.csv
    touch ${prefix}_ctsv_output.rds
    echo "BIOC_CTSV:" > versions.yml
    echo "    ctsv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CTSV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CTSV(ch_input)

    emit:
    results  = BIOC_CTSV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CTSV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CTSV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CTSV.out.versions  // channel: path(versions.yml)
}
