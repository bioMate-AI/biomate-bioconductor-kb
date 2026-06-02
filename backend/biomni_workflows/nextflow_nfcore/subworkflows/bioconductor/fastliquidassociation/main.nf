#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fastLiquidAssociation
// This package extends the function of the LiquidAssociation package for genome-wide application. It i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fastLiquidAssociation/inst/doc/fastLiquidAssociation.R
// Upstream  : GOstats, LiquidAssociation, WGCNA, doParallel, impute
// Downstream: none
//
// Install: BiocManager::install("fastLiquidAssociation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FASTLIQUIDASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fastliquidassociation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fastliquidassociation:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fastliquidassociation:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_fastliquidassociation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fastliquidassociation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fastliquidassociation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fastLiquidAssociation)
    library(CNM)
    library(GLA)
    library(jsonlite)

    # --- Parallelized Liquid Association [] ---
    # Key functions: fastLA
    la_parallel <- fastLA(
        data, 
        percent = 0.1, 
        topn = 20, 
        threads = 2
    )


    # --- Targeted Liquid Association [] ---
    # Key functions: fastLA
    la_targeted <- fastLA(
        data[, 1:10], 
        percent = 0.01, 
        topn = 5
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fastliquidassociation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fastliquidassociation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fastliquidassociation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FASTLIQUIDASSOCIATION:", paste0("    fastliquidassociation: ", packageVersion("fastLiquidAssociation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastliquidassociation_results.csv
    touch ${prefix}_fastliquidassociation_output.rds
    echo "BIOC_FASTLIQUIDASSOCIATION:" > versions.yml
    echo "    fastliquidassociation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FASTLIQUIDASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_FASTLIQUIDASSOCIATION(ch_input)

    emit:
    results  = BIOC_FASTLIQUIDASSOCIATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FASTLIQUIDASSOCIATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FASTLIQUIDASSOCIATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FASTLIQUIDASSOCIATION.out.versions  // channel: path(versions.yml)
}
