#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicTuples
// GenomicTuples defines general purpose containers for storing genomic tuples. It aims to provide func
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicTuples/inst/doc/GenomicTuplesIntroduction.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GenomicTuples")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICTUPLES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomictuples"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomictuples:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomictuples:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomictuples_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomictuples_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomictuples_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GTuples)
    library(GTuplesList)
    library(Seqinfo)
    library(jsonlite)

    # --- Find overlapping genomic intervals [] ---
    # Key functions: GTuples, findOverlaps

    # --- Sequence names check [] ---
    # Key functions: Seqinfo, GTuples, seqnames, tuples, strand, split, window, start


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomictuples_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomictuples_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomictuples_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICTUPLES:", paste0("    genomictuples: ", packageVersion("GenomicTuples"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomictuples_results.csv
    touch ${prefix}_genomictuples_output.rds
    echo "BIOC_GENOMICTUPLES:" > versions.yml
    echo "    genomictuples: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICTUPLES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICTUPLES(ch_input)

    emit:
    results  = BIOC_GENOMICTUPLES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICTUPLES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICTUPLES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICTUPLES.out.versions  // channel: path(versions.yml)
}
