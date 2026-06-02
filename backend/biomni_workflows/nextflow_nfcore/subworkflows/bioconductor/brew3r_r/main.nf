#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BREW3R.r
// This R package provide functions that are used in the BREW3R workflow. This mainly contains a functi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BREW3R.r/inst/doc/BREW3R.r.R
// Upstream  : GenomicRanges, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("BREW3R.r")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BREW3R_R {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-brew3r_r"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-brew3r.r:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-brew3r.r:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_brew3r_r_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_brew3r_r_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_brew3r_r_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BREW3R.r)
    library(jsonlite)

    # --- get GRanges [] ---
    # Key functions: import
    input_gr_to_extend <- rtracklayer::import(input_gtf_file_to_extend)
    input_gr_template <- rtracklayer::import(input_gtf_file_template)
    # --- extend_granges [] ---
    # Key functions: extend_granges
    library(BREW3R.r)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_brew3r_r_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_brew3r_r_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_brew3r_r_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BREW3R_R:", paste0("    brew3r_r: ", packageVersion("BREW3R.r"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_brew3r_r_results.csv
    touch ${prefix}_brew3r_r_output.rds
    echo "BIOC_BREW3R_R:" > versions.yml
    echo "    brew3r_r: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BREW3R_R_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BREW3R_R(ch_input)

    emit:
    results  = BIOC_BREW3R_R.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BREW3R_R.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BREW3R_R.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BREW3R_R.out.versions  // channel: path(versions.yml)
}
