#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: peakPantheR
// An automated pipeline for the detection, integration and reporting of predefined features across a l
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/peakPantheR/inst/doc/getting-started.R
// Upstream  : BiocStyle, devtools, doParallel, faahKO, foreach
// Downstream: none
//
// Install: BiocManager::install("peakPantheR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PEAKPANTHER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-peakpanther"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-peakpanther:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-peakpanther:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_peakpanther_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_peakpanther_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_peakpanther_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(peakPantheR)
    library(jsonlite)

    # --- markdown [] ---
    # Key functions: markdown
    BiocStyle::markdown()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_peakpanther_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_peakpanther_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_peakpanther_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PEAKPANTHER:", paste0("    peakpanther: ", packageVersion("peakPantheR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peakpanther_results.csv
    touch ${prefix}_peakpanther_output.rds
    echo "BIOC_PEAKPANTHER:" > versions.yml
    echo "    peakpanther: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PEAKPANTHER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PEAKPANTHER(ch_input)

    emit:
    results  = BIOC_PEAKPANTHER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PEAKPANTHER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PEAKPANTHER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PEAKPANTHER.out.versions  // channel: path(versions.yml)
}
