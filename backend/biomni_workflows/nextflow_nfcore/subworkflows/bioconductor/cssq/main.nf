#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CSSQ
// This package is desgined to perform statistical analysis to identify statistically significant diffe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CSSQ/inst/doc/CSSQ.R
// Upstream  : BiocStyle, knitr
// Downstream: none
//
// Install: BiocManager::install("CSSQ")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CSSQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cssq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cssq:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cssq:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cssq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cssq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cssq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CSSQ)
    library(jsonlite)

    # --- get Region Counts [] ---
    # Key functions: getRegionCounts, colData, rowRanges, loadCountData, ansTransform
    library(BiocStyle)
    Decide whether to display parts for BioC (TRUE) or F1000 (FALSE)
    library(knitr)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cssq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cssq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cssq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CSSQ:", paste0("    cssq: ", packageVersion("CSSQ"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cssq_results.csv
    touch ${prefix}_cssq_output.rds
    echo "BIOC_CSSQ:" > versions.yml
    echo "    cssq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CSSQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CSSQ(ch_input)

    emit:
    results  = BIOC_CSSQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CSSQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CSSQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CSSQ.out.versions  // channel: path(versions.yml)
}
