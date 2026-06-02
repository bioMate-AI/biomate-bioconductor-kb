#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SPsimSeq
// SPsimSeq uses a specially designed exponential family for density estimation to constructs the distr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SPsimSeq/inst/doc/SPsimSeq.R
// Upstream  : devtools, BiocManager, LSD, SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("SPsimSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPSIMSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spsimseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spsimseq:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spsimseq:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spsimseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spsimseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spsimseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SPsimSeq)
    library(jsonlite)

    # --- heatscatter [] ---
    # Key functions: heatscatter, ifelse, loess
    par(mfrow=c(1,3), mar=c(4,4,4,1))
    # --- col Data [] ---
    # Key functions: colData, rowData
    class(sim.data.sc1)
    head(counts(sim.data.sc1)[, seq_len(5)])
    colData(sim.data.sc1)
    # --- heatscatter [] ---
    # Key functions: heatscatter, ifelse, loess
    par(mfrow=c(1,3), mar=c(4,4,4,1))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spsimseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spsimseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spsimseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPSIMSEQ:", paste0("    spsimseq: ", packageVersion("SPsimSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spsimseq_results.csv
    touch ${prefix}_spsimseq_output.rds
    echo "BIOC_SPSIMSEQ:" > versions.yml
    echo "    spsimseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPSIMSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPSIMSEQ(ch_input)

    emit:
    results  = BIOC_SPSIMSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPSIMSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPSIMSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPSIMSEQ.out.versions  // channel: path(versions.yml)
}
