#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rhdf5client
// This package provides functionality for reading data from HDF Scalable Data Service from within R.  
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rhdf5client/inst/doc/delayed-array.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rhdf5client")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_RHDF5CLIENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rhdf5client"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rhdf5client_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rhdf5client_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rhdf5client_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rhdf5client)
    library(HSDSArray)
    library(jsonlite)

    # --- HSDS Server Connection and Verification [] ---
    # Key functions: check_hsds, URL_hsds, HSDSSource
    hsds_active <- check_hsds()
    if (hsds_active) {
        endpoint_url <- URL_hsds()
        hsds_source <- HSDSSource(endpoint_url)
    }

    # --- Remote Genomic Dataset Exploration [] ---
    # Key functions: URL_hsds, HSDSSource, HSDSFile, HSDSDataset
    endpoint_url <- URL_hsds()
    hsds_source <- HSDSSource(endpoint_url)
    file_path <- "/shared/bioconductor/patelGBMSC.h5"
    file_obj <- HSDSFile(hsds_source, file_path)
    dataset_obj <- HSDSDataset(file_obj, "/assay001")

    # --- DelayedArray Representation of Genomic Data [] ---
    # Key functions: URL_hsds, HSDSArray
    endpoint_url <- URL_hsds()
    da <- HSDSArray(
        endpoint = endpoint_url,
        domain = "hsds",
        filepath = "/shared/bioconductor/patelGBMSC.h5",
        host = "/assay001"
    )
    da_dims <- dim(da)

    # --- Expression Matrix Aggregation [] ---
    # Key functions: URL_hsds, HSDSArray
    endpoint_url <- URL_hsds()
    da <- HSDSArray(
        endpoint = endpoint_url,
        domain = "hsds",
        filepath = "/shared/bioconductor/patelGBMSC.h5",
        host = "/assay001"
    )
    sub_matrix <- da[, 1:4]
    column_sums <- apply(sub_matrix, 2, sum)


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
        write.csv(as.data.frame(.main), "${prefix}_rhdf5client_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rhdf5client_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rhdf5client_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RHDF5CLIENT:", paste0("    rhdf5client: ", as.character(packageVersion("rhdf5client")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rhdf5client_results.csv
    touch ${prefix}_rhdf5client_output.rds
    echo "BIOC_RHDF5CLIENT:" > versions.yml
    echo "    rhdf5client: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RHDF5CLIENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RHDF5CLIENT(ch_input)

    emit:
    results  = BIOC_RHDF5CLIENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RHDF5CLIENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RHDF5CLIENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RHDF5CLIENT.out.versions  // channel: path(versions.yml)
}
