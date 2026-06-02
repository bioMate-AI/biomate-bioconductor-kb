#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dmrseq
// This package implements an approach for scanning the genome to detect and perform accurate inference
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dmrseq/inst/doc/dmrseq.R
// Upstream  : BiocParallel
// Downstream: none
//
// Install: BiocManager::install("dmrseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DMRSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dmrseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dmrseq:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dmrseq:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dmrseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dmrseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dmrseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BSseq)
    library(jsonlite)

    # --- Phenotype data inspection [] ---
    # Key functions: BSseq, pData, dmrseq, getCoverage, start, sampleNames, show, register
    pData(bs)$CellType <- celltype
    pData(bs)$Replicate <- substr(sampleNames,
    nchar(sampleNames), nchar(sampleNames))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dmrseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dmrseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dmrseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DMRSEQ:", paste0("    dmrseq: ", packageVersion("dmrseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmrseq_results.csv
    touch ${prefix}_dmrseq_output.rds
    echo "BIOC_DMRSEQ:" > versions.yml
    echo "    dmrseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DMRSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DMRSEQ(ch_input)

    emit:
    results  = BIOC_DMRSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DMRSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DMRSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DMRSEQ.out.versions  // channel: path(versions.yml)
}
