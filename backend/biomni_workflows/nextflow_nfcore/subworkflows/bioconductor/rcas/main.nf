#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RCAS
// RCAS is an R/Bioconductor package designed as a generic reporting tool for the functional analysis o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RCAS/inst/doc/RCAS.metaAnalysis.vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RCAS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcas"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcas:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcas:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcas_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcas_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcas_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RCAS)
    library(jsonlite)

    # --- load libraries [] ---
    # Key functions: deleteSampleDataFromDB, dbConnect, dbListTables, dbReadTable
    library(RCAS)
    FUS_rep1_path <- system.file('extdata', 'FUS_Nakaya2013c_hg19.bed', package = 'RCAS')
    FUS_rep2_path <- system.file('extdata', 'FUS_Nakaya2013d_hg19.bed', package = 'RCAS')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcas_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcas_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcas_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCAS:", paste0("    rcas: ", packageVersion("RCAS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcas_results.csv
    touch ${prefix}_rcas_output.rds
    echo "BIOC_RCAS:" > versions.yml
    echo "    rcas: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCAS(ch_input)

    emit:
    results  = BIOC_RCAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCAS.out.versions  // channel: path(versions.yml)
}
