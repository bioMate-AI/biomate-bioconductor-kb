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
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    library(Spectra)
    library(jsonlite)

    # --- warnings = FALSE [] ---
    # Key functions: setBackend, spectraVariables, peaksData, reset, Spectra
    sps2 <- setBackend(sps_mem, MsBackendOfflineSql(), drv = SQLite(),
    dbname = tempfile())
    spectraVariables(sps)

    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_msbackendsql_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_msbackendsql_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_msbackendsql_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDSQL:", paste0("    msbackendsql: ", as.character(packageVersion("MsBackendSql")))),
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
