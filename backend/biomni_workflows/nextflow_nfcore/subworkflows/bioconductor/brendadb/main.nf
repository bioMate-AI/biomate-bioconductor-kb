#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: brendaDb
// R interface for importing and analyzing enzyme information from the BRENDA database.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/brendaDb/inst/doc/brendaDb.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("brendaDb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BRENDADB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-brendadb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-brendadb:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-brendadb:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(deseq2results)

    output:
    tuple val(meta), path("${meta.id}_brendadb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_brendadb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_brendadb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExtractField)
    library(ID2Enzyme)
    library(QueryBrenda)
    library(ShowFields)
    library(jsonlite)

    # --- Showfields [] ---
    # Key functions: ShowFields, QueryBrenda
    ---------------------------------------------------------------------
    ShowFields(df)
    res <- QueryBrenda(df, EC = "1.1.1.1", fields = c("PROTEIN", "SUBSTRATE_PRODUCT"))
    res[["1.1.1.1"]][["interactions"]][["substrate.product"]]
    # --- Querybrenda [] ---
    # Key functions: QueryBrenda
    ---------------------------------------------------------------------
    res <- QueryBrenda(df, EC = "1.1.1.1", organisms = "Homo sapiens")
    res$`1.1.1.1`
    # --- Querybrenda [] ---
    # Key functions: QueryBrenda, ExtractField
    ---------------------------------------------------------------------
    res <- QueryBrenda(df, EC = c("1.1.1.1", "6.3.5.8"), n.core = 2)
    ExtractField(res, field = "parameters$ph.optimum")
    # --- I D2 Enzyme [] ---
    # Key functions: ID2Enzyme
    ---------------------------------------------------------------------
    ID2Enzyme(brenda = df, ids = c("ADH4", "CD38", "pyruvate dehydrogenase"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_brendadb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_brendadb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_brendadb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BRENDADB:", paste0("    brendadb: ", packageVersion("brendaDb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_brendadb_results.csv
    touch ${prefix}_brendadb_output.rds
    echo "BIOC_BRENDADB:" > versions.yml
    echo "    brendadb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BRENDADB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseq2results) ]

    main:
    BIOC_BRENDADB(ch_input)

    emit:
    results  = BIOC_BRENDADB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BRENDADB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BRENDADB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BRENDADB.out.versions  // channel: path(versions.yml)
}
