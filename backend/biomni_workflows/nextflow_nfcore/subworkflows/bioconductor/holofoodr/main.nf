#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HoloFoodR
// Utility package to facilitate integration and analysis of EBI HoloFood data in R. This package strea
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HoloFoodR/inst/doc/HoloFoodR.R
// Upstream  : MGnifyR, knitr
// Downstream: none
//
// Install: BiocManager::install("HoloFoodR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HOLOFOODR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-holofoodr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-holofoodr:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-holofoodr:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_holofoodr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_holofoodr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_holofoodr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MgnifyClient)
    library(jsonlite)

    # --- Retrieve data from repository [] ---
    # Key functions: getData
    animal_data <- getData(
    # --- DoQuery analysis [] ---
    # Key functions: doQuery, getResult, MgnifyClient, searchAnalysis, experiments, getMetaboLights
    exps <- experiments(mae_metagenomic)
    exps <- lapply(exps, function(x){
    sample_id <- names(analysis_ids)[ match(colnames(x), analysis_ids) ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_holofoodr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_holofoodr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_holofoodr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HOLOFOODR:", paste0("    holofoodr: ", packageVersion("HoloFoodR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_holofoodr_results.csv
    touch ${prefix}_holofoodr_output.rds
    echo "BIOC_HOLOFOODR:" > versions.yml
    echo "    holofoodr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HOLOFOODR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HOLOFOODR(ch_input)

    emit:
    results  = BIOC_HOLOFOODR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HOLOFOODR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HOLOFOODR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HOLOFOODR.out.versions  // channel: path(versions.yml)
}
