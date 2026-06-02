#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SRAdb
// The Sequence Read Archive (SRA) is the largest public repository of sequencing data from the next ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SRAdb/inst/doc/SRAdb.R
// Upstream  : Rgraphviz
// Downstream: none
//
// Install: BiocManager::install("SRAdb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SRADB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sradb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sradb:1.68.1--r44_0' :
        'quay.io/biocontainers/bioconductor-sradb:1.68.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sradb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sradb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sradb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SRAdb)
    library(SQLite)
    library(TABLE_INFO)
    library(jsonlite)

    # --- Targeted Metadata Retrieval [] ---
    # Key functions: dbGetQuery
    query_str <- paste(
        "select study_accession, study_title from study where",
        "study_description like 'Transcriptome%'",
        sep = " "
    )
    transcriptome_studies <- dbGetQuery(sra_con, query_str)


    # --- Entity Attribute Extraction [] ---
    # Key functions: dbGetQuery
    sample_query <- "select sample_accession, run_accession from sra limit 5"
    sample_runs <- dbGetQuery(sra_con, sample_query)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sradb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sradb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sradb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SRADB:", paste0("    sradb: ", packageVersion("SRAdb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sradb_results.csv
    touch ${prefix}_sradb_output.rds
    echo "BIOC_SRADB:" > versions.yml
    echo "    sradb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SRADB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SRADB(ch_input)

    emit:
    results  = BIOC_SRADB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SRADB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SRADB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SRADB.out.versions  // channel: path(versions.yml)
}
