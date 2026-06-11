#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gDRutils
// This package contains utility functions used throughout the gDR platform to fit data, manipulate dat
//
// Input: mae.rds (serialized MultiAssayExperiment from the gDR pipeline, with a "Metrics" assay)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gDRutils/inst/doc/gDRutils.R
// Upstream  : none
// Downstream: gDR
//
// Install: BiocManager::install("gDRutils")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_GDRUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gdrutils"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gdrutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gdrutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gdrutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gDRutils)
    library(MultiAssayExperiment)
    library(jsonlite)

    # --- Load user-provided input ---
    # mae.rds: a serialized MultiAssayExperiment produced by the gDR pipeline
    #          (gDRcore output), containing dose-response SummarizedExperiments
    #          with a "Metrics" assay.
    mae <- readRDS("mae.rds")

    # --- Data Loading and Inspection [] ---
    # Key functions: MAEpply
    mae_dims <- MAEpply(mae, dim)
    mae_rowdata <- MAEpply(mae, rowData, unify = TRUE)
    se_obj <- mae[[1]]

    # --- Format Conversion [] ---
    # Key functions: convert_mae_assay_to_dt, convert_se_assay_to_dt
    metrics_dt <- convert_mae_assay_to_dt(mae, "Metrics")
    se_obj <- mae[[1]]
    se_metrics_dt <- convert_se_assay_to_dt(se_obj, "Metrics")
    dt_cols <- colnames(metrics_dt)

    # --- Identifier Management [] ---
    # Key functions: get_env_identifiers, set_env_identifier, reset_env_identifiers
    current_ids <- get_env_identifiers()
    set_env_identifier("concentration", "Dose")
    updated_conc <- get_env_identifiers("concentration")
    reset_env_identifiers()
    restored_conc <- get_env_identifiers("concentration")

    # --- Validation and Prettification [] ---
    # Key functions: validate_MAE, validate_SE, prettify_flat_metrics
    se_obj <- mae[[1]]
    mae_valid <- validate_MAE(mae)
    se_valid <- validate_SE(se_obj)
    raw_names <- c("CellLineName", "Tissue", "Concentration_2")
    pretty_names <- prettify_flat_metrics(
        raw_names,
        human_readable = TRUE
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
        write.csv(as.data.frame(.main), "${prefix}_gdrutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_gdrutils_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_gdrutils_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_GDRUTILS:", paste0("    gdrutils: ", as.character(packageVersion("gDRutils")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdrutils_results.csv
    touch ${prefix}_gdrutils_output.rds
    echo "BIOC_GDRUTILS:" > versions.yml
    echo "    gdrutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GDRUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GDRUTILS(ch_input)

    emit:
    results  = BIOC_GDRUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GDRUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GDRUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GDRUTILS.out.versions  // channel: path(versions.yml)
}
