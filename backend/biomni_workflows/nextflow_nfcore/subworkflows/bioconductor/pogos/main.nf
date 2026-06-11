#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pogos
// Provide simple utilities for querying bhklab PharmacoDB, modeling API outputs, and integrating to ce
//
// Input: query.csv  (user-provided query table; columns: dataset, cell_line; one row per dose-response query to retrieve from PharmacoDB)
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pogos/inst/doc/pogos.R
// Upstream  : ggplot2, httr, ontoProc, ontologyPlot, rjson
// Downstream: none
//
// Install: BiocManager::install("pogos")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_POGOS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pogos"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pogos_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pogos_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pogos_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pogos)
    library(jsonlite)

    # --- Read USER INPUT: query table -------------------------------------------
    # Each row specifies a PharmacoDB dose-response query (dataset + optional cell_line).
    .query_file <- if (file.exists("query.csv")) "query.csv" else if (file.exists("query.tsv")) "query.tsv" else NA_character_
    if (is.na(.query_file)) {
        stop("Required input file 'query.csv' (columns: dataset[, cell_line]) not found in the working directory.")
    }
    query_df <- if (grepl("\\\\.tsv\$", .query_file)) {
        read.delim(.query_file, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)
    } else {
        read.csv(.query_file, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)
    }
    if (!"dataset" %in% colnames(query_df)) {
        stop("Input query table must contain a 'dataset' column (e.g. 'CCLE').")
    }

    # --- Retrieve dose-response traces for each requested dataset ----------------
    # Key functions: DRTraceSet (queries the live bhklab PharmacoDB REST API)
    trace_results <- list()
    for (.i in seq_len(nrow(query_df))) {
        .ds <- as.character(query_df\$dataset[.i])
        .ts <- tryCatch(DRTraceSet(dataset = .ds), error = function(e) NULL)
        if (!is.null(.ts) && !inherits(.ts, "try-error")) {
            trace_results[[.ds]] <- .ts
            tryCatch(plot(.ts), error = function(e) NULL)
        } else {
            message("Note: dose-response retrieval for dataset '", .ds, "' failed (PharmacoDB may be unavailable).")
        }
    }

    # --- Retrieve per-cell-line dose-response profiles if cell_line column given -
    # Key functions: DRProfSet
    prof_results <- list()
    if ("cell_line" %in% colnames(query_df)) {
        for (.i in seq_len(nrow(query_df))) {
            .cl <- as.character(query_df\$cell_line[.i])
            if (is.na(.cl) || !nzchar(.cl)) next
            .pr <- tryCatch(DRProfSet(cell_line = .cl), error = function(e) NULL)
            if (!is.null(.pr) && !inherits(.pr, "try-error")) {
                prof_results[[.cl]] <- .pr
                tryCatch(plot(.pr), error = function(e) NULL)
            }
        }
    }

    # Tabulate what was successfully retrieved for the results CSV
    query_summary <- data.frame(
        row          = seq_len(nrow(query_df)),
        dataset      = as.character(query_df\$dataset),
        cell_line    = if ("cell_line" %in% colnames(query_df)) as.character(query_df\$cell_line) else NA_character_,
        trace_retrieved = vapply(as.character(query_df\$dataset), function(d) d %in% names(trace_results), logical(1)),
        stringsAsFactors = FALSE
    )


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
        write.csv(as.data.frame(.main), "${prefix}_pogos_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_pogos_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_pogos_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_POGOS:", paste0("    pogos: ", as.character(packageVersion("pogos")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pogos_results.csv
    touch ${prefix}_pogos_output.rds
    echo "BIOC_POGOS:" > versions.yml
    echo "    pogos: 0.0.0" >> versions.yml
    """
}


workflow BIOC_POGOS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(query_csv) ]

    main:
    BIOC_POGOS(ch_input)

    emit:
    results  = BIOC_POGOS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_POGOS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_POGOS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_POGOS.out.versions  // channel: path(versions.yml)
}
