#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: odseq
// Performs outlier detection of sequences in a multiple sequence alignment using bootstrap of predefin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/odseq/inst/doc/vignette.R
// Upstream  : kebabs, msa
// Downstream: none
//
// Install: BiocManager::install("odseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ODSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-odseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-odseq:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-odseq:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_odseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_odseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_odseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(odseq)
    library(jsonlite)

    # --- Msa [] ---
    # Key functions: msa
    ---------------------------------------------------------------------
    library(msa)
    alig <- msa(seqs)
    # --- Spectrumkernel [] ---
    # Key functions: spectrumKernel, getKernelMatrix
    ---------------------------------------------------------------------
    library(kebabs)
    sp <- spectrumKernel(k = 3)
    mat <- getKernelMatrix(sp, seqs)
    # --- Odseq Unaligned [] ---
    # Key functions: odseq_unaligned
    ---------------------------------------------------------------------
    outliers_unaligned <- odseq_unaligned(mat, B = 1000, type = "similarity")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_odseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_odseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_odseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ODSEQ:", paste0("    odseq: ", packageVersion("odseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_odseq_results.csv
    touch ${prefix}_odseq_output.rds
    echo "BIOC_ODSEQ:" > versions.yml
    echo "    odseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ODSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ODSEQ(ch_input)

    emit:
    results  = BIOC_ODSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ODSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ODSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ODSEQ.out.versions  // channel: path(versions.yml)
}
