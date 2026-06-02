#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biodbHmdb
// The biodbHmdb library is an extension of the biodb framework package that provides access to the HMD
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biodbHmdb/inst/doc/biodbHmdb.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biodbHmdb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBHMDB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biodbhmdb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biodbhmdb:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biodbhmdb:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biodbhmdb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biodbhmdb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biodbhmdb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biodbHmdb)
    library(jsonlite)

    # --- kable [] ---
    # Key functions: kable
    knitr::kable(entryDf, "pipe", caption="The entry returned when searching by name.")
    id <- conn$searchForEntries(list(description=c('Parkinson', 'sclerosis')), max.results=1)
    entryDf <- conn$getEntry(id)$getFieldsAsDataframe(fields=c('accession', 'name', 'description'))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biodbhmdb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biodbhmdb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biodbhmdb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIODBHMDB:", paste0("    biodbhmdb: ", packageVersion("biodbHmdb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biodbhmdb_results.csv
    touch ${prefix}_biodbhmdb_output.rds
    echo "BIOC_BIODBHMDB:" > versions.yml
    echo "    biodbhmdb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIODBHMDB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIODBHMDB(ch_input)

    emit:
    results  = BIOC_BIODBHMDB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIODBHMDB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIODBHMDB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIODBHMDB.out.versions  // channel: path(versions.yml)
}
