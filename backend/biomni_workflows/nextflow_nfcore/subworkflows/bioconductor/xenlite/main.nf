#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: xenLite
// Define a relatively light class for managing Xenium data using Bioconductor.  Address use of parquet
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/xenLite/inst/doc/xenLite.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("xenLite")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XENLITE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xenlite"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xenlite_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xenlite_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xenlite_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(xenLite)
    library(jsonlite)

    # --- cache Xen Luad [] ---
    # Key functions: cacheXenLuad, restoreZipXenSPEP, viewSegG2
    library(xenLite)
    pa <- cacheXenLuad()
    luad <- restoreZipXenSPEP(pa)
    # --- cache Xen Prost Lite [] ---
    # Key functions: cacheXenProstLite
    prost <- cacheXenProstLite()
    # --- unzip [] ---
    # Key functions: unzip
    dir.create(xpw <- file.path(tempdir(), "prost_work"))
    unzip(prost, exdir = xpw)
    dir(xpw)
    # --- load H D F5 Summarized Experiment [] ---
    # Key functions: loadHDF5SummarizedExperiment
    prostx <- HDF5Array::loadHDF5SummarizedExperiment(file.path(xpw, "xen_prost"))

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
        write.csv(as.data.frame(.main), "${prefix}_xenlite_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_xenlite_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_xenlite_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_XENLITE:", paste0("    xenlite: ", as.character(packageVersion("xenLite")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xenlite_results.csv
    touch ${prefix}_xenlite_output.rds
    echo "BIOC_XENLITE:" > versions.yml
    echo "    xenlite: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XENLITE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XENLITE(ch_input)

    emit:
    results  = BIOC_XENLITE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XENLITE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XENLITE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XENLITE.out.versions  // channel: path(versions.yml)
}
