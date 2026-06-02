#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EpiTxDb
// EpiTxDb facilitates the storage of epitranscriptomic information. More specifically, it can keep tra
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EpiTxDb/inst/doc/EpiTxDb-creation.R
// Upstream  : GenomicRanges, ggplot2
// Downstream: EpiTxDb.Hs.hg38, EpiTxDb.Mm.mm10, EpiTxDb.Sc.sacCer3
//
// Install: BiocManager::install("EpiTxDb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPITXDB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epitxdb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epitxdb:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epitxdb:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epitxdb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epitxdb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epitxdb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EpiTxDb)
    library(DataFrame)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Database Querying [] ---
    # Key functions: modifications, modificationsBy
    mods <- modifications(etdb)
    mods_by_tx <- modificationsBy(etdb, by = "tx")


    # --- Metadata Retrieval [] ---
    # Key functions: metadata
    meta_info <- metadata(etdb)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epitxdb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epitxdb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epitxdb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPITXDB:", paste0("    epitxdb: ", packageVersion("EpiTxDb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epitxdb_results.csv
    touch ${prefix}_epitxdb_output.rds
    echo "BIOC_EPITXDB:" > versions.yml
    echo "    epitxdb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPITXDB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPITXDB(ch_input)

    emit:
    results  = BIOC_EPITXDB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPITXDB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPITXDB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPITXDB.out.versions  // channel: path(versions.yml)
}
