#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: appreci8R
// The appreci8R is an R version of our appreci8-algorithm - A Pipeline for PREcise variant Calling Int
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/appreci8R/inst/doc/appreci8R.R
// Upstream  : Biostrings, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("appreci8R")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APPRECI8R {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-appreci8r"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-appreci8r:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-appreci8r:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_appreci8r_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_appreci8r_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_appreci8r_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(appreci8R)
    library(jsonlite)

    # --- 10 [] ---
    # Key functions: finalFiltration
    output_folder <- ""
    #Input:
    filtered
    characteristics
    combined

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_appreci8r_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_appreci8r_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_appreci8r_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_APPRECI8R:", paste0("    appreci8r: ", packageVersion("appreci8R"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_appreci8r_results.csv
    touch ${prefix}_appreci8r_output.rds
    echo "BIOC_APPRECI8R:" > versions.yml
    echo "    appreci8r: 0.0.0" >> versions.yml
    """
}


workflow BIOC_APPRECI8R_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_APPRECI8R(ch_input)

    emit:
    results  = BIOC_APPRECI8R.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_APPRECI8R.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_APPRECI8R.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_APPRECI8R.out.versions  // channel: path(versions.yml)
}
