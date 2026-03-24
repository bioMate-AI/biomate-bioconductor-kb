#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: singleCellTK
// The Single Cell Toolkit (SCTK) in the singleCellTK package provides an interface to popular tools fo
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/singleCellTK/inst/doc/singleCellTK.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("singleCellTK")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGLECELLTK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singlecelltk"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-singlecelltk:2.16.1--r44_0' :
        'quay.io/biocontainers/bioconductor-singlecelltk:2.16.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_singlecelltk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singlecelltk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singlecelltk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(singleCellTK)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: 2, namespace
    ## R version 4.4.2 (2024-10-31)
    ## Platform: x86_64-pc-linux-gnu
    ## Running under: Ubuntu 24.04.2 LTS
    ##
    ## Matrix products: default

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_singlecelltk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_singlecelltk_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_singlecelltk_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGLECELLTK:", paste0("    singlecelltk: ", packageVersion("singleCellTK"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singlecelltk_results.csv
    touch ${prefix}_singlecelltk_output.rds
    echo "BIOC_SINGLECELLTK:" > versions.yml
    echo "    singlecelltk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGLECELLTK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SINGLECELLTK(ch_input)

    emit:
    results  = BIOC_SINGLECELLTK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGLECELLTK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGLECELLTK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGLECELLTK.out.versions  // channel: path(versions.yml)
}
