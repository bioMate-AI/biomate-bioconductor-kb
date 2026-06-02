#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendSql
// SQL-based mass spectrometry (MS) data backend supporting also storange and handling of very large da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendSql/inst/doc/MsBackendSql.R
// Upstream  : BiocStyle, RSQLite, microbenchmark
// Downstream: none
//
// Install: BiocManager::install("MsBackendSql")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSBACKENDSQL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendsql"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msbackendsql:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msbackendsql:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msbackendsql_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msbackendsql_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msbackendsql_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MsBackendSql)
    library(jsonlite)


    # --- Warnings = False [] ---
    # Key functions: setBackend, MsBackendOfflineSql, SQLite, tempfile, spectraVariables, peaksData, object.size
    sps2 <- setBackend(sps_mem, MsBackendOfflineSql(), drv = SQLite(),
                       dbname = tempfile())
    sps2

    ## -----------------------------------------------------------------------------
    spectraVariables(sps)

    ## -----------------------------------------------------------------------------
    peaksData(sps)[[5]] |>
    head()

    ## -----------------------------------------------------------------------------
    print(object.size(sps), units = "KB")

    ## -----------------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msbackendsql_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msbackendsql_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msbackendsql_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDSQL:", paste0("    msbackendsql: ", packageVersion("MsBackendSql"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendsql_results.csv
    touch ${prefix}_msbackendsql_output.rds
    echo "BIOC_MSBACKENDSQL:" > versions.yml
    echo "    msbackendsql: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDSQL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSBACKENDSQL(ch_input)

    emit:
    results  = BIOC_MSBACKENDSQL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSBACKENDSQL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSBACKENDSQL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSBACKENDSQL.out.versions  // channel: path(versions.yml)
}
