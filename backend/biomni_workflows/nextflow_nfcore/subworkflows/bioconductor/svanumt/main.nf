#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: svaNUMT
// svaNUMT contains functions for detecting NUMT events from structural variant calls. It takes structu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/svaNUMT/inst/doc/svaNUMT.R
// Upstream  : StructuralVariantAnnotation, VariantAnnotation, circlize, readr
// Downstream: none
//
// Install: BiocManager::install("svaNUMT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SVANUMT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-svanumt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-svanumt:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-svanumt:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_svanumt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_svanumt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_svanumt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(svaNUMT)
    library(jsonlite)

    # --- Read VCF variant file [] ---
    # Key functions: readVcf, breakpointRanges
    library(StructuralVariantAnnotation)
    library(VariantAnnotation)
    library(svaNUMT)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_svanumt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_svanumt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_svanumt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SVANUMT:", paste0("    svanumt: ", packageVersion("svaNUMT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_svanumt_results.csv
    touch ${prefix}_svanumt_output.rds
    echo "BIOC_SVANUMT:" > versions.yml
    echo "    svanumt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SVANUMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SVANUMT(ch_input)

    emit:
    results  = BIOC_SVANUMT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SVANUMT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SVANUMT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SVANUMT.out.versions  // channel: path(versions.yml)
}
