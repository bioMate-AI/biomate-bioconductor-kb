#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MADSEQ
// The MADSEQ package provides a group of hierarchical Bayeisan models for the detection of mosaic aneu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MADSEQ/inst/doc/MADSEQ-vignette.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("MADSEQ")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MADSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-madseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-madseq:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-madseq:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_madseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_madseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_madseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MADSEQ)
    library(jsonlite)

    # --- Normalizecoverage [] ---
    # Key functions: normalizeCoverage
    ---------------------------------------------------------------------
    ## normalize coverage data
    ## set plot=FALSE here because similar plot will show in the following example
    normalizeCoverage(aneuploidy_cov,writeToFile=TRUE, destination=".",plot=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_madseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_madseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_madseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MADSEQ:", paste0("    madseq: ", packageVersion("MADSEQ"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_madseq_results.csv
    touch ${prefix}_madseq_output.rds
    echo "BIOC_MADSEQ:" > versions.yml
    echo "    madseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MADSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MADSEQ(ch_input)

    emit:
    results  = BIOC_MADSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MADSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MADSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MADSEQ.out.versions  // channel: path(versions.yml)
}
