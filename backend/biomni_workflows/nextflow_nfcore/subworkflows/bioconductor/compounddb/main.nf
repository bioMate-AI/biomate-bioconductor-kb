#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CompoundDb
// CompoundDb provides functionality to create and use (chemical) compound annotation databases from a 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CompoundDb/inst/doc/CompoundDb-usage.R
// Upstream  : BiocStyle, MsBackendMgf, RSQLite, Spectra
// Downstream: none
//
// Install: BiocManager::install("CompoundDb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMPOUNDDB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-compounddb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-compounddb:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-compounddb:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_compounddb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_compounddb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_compounddb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CompoundDb)
    library(jsonlite)


    # --- Load [] ---
    # Key functions: CompDb, metadata, compoundVariables, compounds, name, formula, exactmass, compound_id
    library(CompoundDb)
    cdb <- CompDb(system.file("sql/CompDb.MassBank.sql", package = "CompoundDb"))
    cdb

    ## -----------------------------------------------------------------------------
    metadata(cdb)

    ## -----------------------------------------------------------------------------
    compoundVariables(cdb)

    ## -----------------------------------------------------------------------------
    head(compounds(cdb, columns = c("name", "formula", "exactmass")))

    ## -----------------------------------------------------------------------------
    head(compounds(cdb, columns = c("compound_id", "name", "formula")))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_compounddb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_compounddb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_compounddb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMPOUNDDB:", paste0("    compounddb: ", packageVersion("CompoundDb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compounddb_results.csv
    touch ${prefix}_compounddb_output.rds
    echo "BIOC_COMPOUNDDB:" > versions.yml
    echo "    compounddb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMPOUNDDB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMPOUNDDB(ch_input)

    emit:
    results  = BIOC_COMPOUNDDB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMPOUNDDB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMPOUNDDB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMPOUNDDB.out.versions  // channel: path(versions.yml)
}
