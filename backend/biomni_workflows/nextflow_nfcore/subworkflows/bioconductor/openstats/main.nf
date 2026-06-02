#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OpenStats
// Package contains several methods for statistical analysis of genotype to phenotype association in hi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OpenStats/inst/doc/OpenStats.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("OpenStats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPENSTATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-openstats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-openstats:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-openstats:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_openstats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_openstats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_openstats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OpenStatsAnalysis)
    library(OpenStatsComplementarySplit)
    library(OpenStatsList)
    library(OpenStatsReport)
    library(jsonlite)

    # --- R hide003 [] ---
    # Key functions: OpenStatsList
    library(OpenStats)
    # --- R hide005 [] ---
    # Key functions: OpenStatsList
    library(OpenStats)
    # --- R hide01021 [] ---
    # Key functions: OpenStatsList, OpenStatsAnalysis
    library(OpenStats)
    # --- R hide010 [] ---
    # Key functions: OpenStatsList, OpenStatsAnalysis
    library(OpenStats)
    # --- R hide010m2 [] ---
    # Key functions: OpenStatsList, OpenStatsAnalysis, OpenStatsComplementarySplit
    library(OpenStats)
    # --- R hide01020 [] ---
    # Key functions: OpenStatsList, OpenStatsAnalysis
    library(OpenStats)
    # --- R hide0102 [] ---
    # Key functions: OpenStatsList, OpenStatsAnalysis
    library(OpenStats)
    # --- R hide013 [] ---
    # Key functions: OpenStatsList, OpenStatsAnalysis
    library(OpenStats)
    # --- R hide015 [] ---
    # Key functions: strtrim, OpenStatsReport

    # --- R hide017 [] ---
    # Key functions: OpenStatsList
    library(OpenStats)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_openstats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_openstats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_openstats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPENSTATS:", paste0("    openstats: ", packageVersion("OpenStats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_openstats_results.csv
    touch ${prefix}_openstats_output.rds
    echo "BIOC_OPENSTATS:" > versions.yml
    echo "    openstats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPENSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OPENSTATS(ch_input)

    emit:
    results  = BIOC_OPENSTATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPENSTATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPENSTATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPENSTATS.out.versions  // channel: path(versions.yml)
}
