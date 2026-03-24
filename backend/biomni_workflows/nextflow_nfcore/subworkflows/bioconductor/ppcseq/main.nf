#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ppcseq
// Relative transcript abundance has proven to be a valuable tool for understanding the function of gen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ppcseq/inst/doc/introduction.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("ppcseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PPCSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ppcseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ppcseq:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ppcseq:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ppcseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ppcseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ppcseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ppcseq)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("counts")
    counts

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ppcseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ppcseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ppcseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PPCSEQ:", paste0("    ppcseq: ", packageVersion("ppcseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ppcseq_results.csv
    touch ${prefix}_ppcseq_output.rds
    echo "BIOC_PPCSEQ:" > versions.yml
    echo "    ppcseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PPCSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PPCSEQ(ch_input)

    emit:
    results  = BIOC_PPCSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PPCSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PPCSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PPCSEQ.out.versions  // channel: path(versions.yml)
}
