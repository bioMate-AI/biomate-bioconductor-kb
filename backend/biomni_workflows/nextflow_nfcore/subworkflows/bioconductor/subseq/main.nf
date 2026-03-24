#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: subSeq
// Subsampling of high throughput sequencing count data for use in experiment design and analysis.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/subSeq/inst/doc/subSeq.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("subSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SUBSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-subseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-subseq:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-subseq:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_subseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_subseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_subseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(subSeq)
    library(jsonlite)

    # --- package Description [] ---
    # Key functions: packageDescription
    options(keep.source = TRUE, width = 48)
    foo <- packageDescription("subSeq")
    # --- custom ggplot2 [] ---
    # Key functions: ggplot
    library(ggplot2)
    ggplot(subsamples.summary, aes(x=depth, y=percent, col=method)) + geom_line()
    # --- custom ggplot2 2 [] ---
    # Key functions: ggplot
    ggplot(subsamples.summary, aes(x=depth, y=pearson, col=method)) + geom_line()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_subseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_subseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_subseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SUBSEQ:", paste0("    subseq: ", packageVersion("subSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subseq_results.csv
    touch ${prefix}_subseq_output.rds
    echo "BIOC_SUBSEQ:" > versions.yml
    echo "    subseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SUBSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SUBSEQ(ch_input)

    emit:
    results  = BIOC_SUBSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SUBSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SUBSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SUBSEQ.out.versions  // channel: path(versions.yml)
}
