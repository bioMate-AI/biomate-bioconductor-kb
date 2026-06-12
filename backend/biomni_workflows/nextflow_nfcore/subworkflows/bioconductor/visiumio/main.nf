#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VisiumIO
// The package allows users to readily import spatial data obtained from either the 10X website or from
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VisiumIO/inst/doc/VisiumIO.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("VisiumIO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VISIUMIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-visiumio"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_visiumio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_visiumio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_visiumio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("VisiumIO", "TENxVisiumHD", "TENxVisiumList", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(VisiumIO)
    library(TENxVisiumHD)
    library(TENxVisiumList)
    library(jsonlite)

    # --- Single Sample Import [Importing a single Visium sample] ---
    # Key functions: TENxVisium, import
    vis <- TENxVisium(
        spacerangerOut = "path/to/10x/visium/sample/folder",
        processing = "raw",
        images = "lowres"
    )
    spe <- import(vis)

    # --- Multi-Sample Import [Importing multiple Visium samples] ---
    # Key functions: TENxVisiumList, import
    vlist <- TENxVisiumList(
        sampleFolders = c("path/to/sample01", "path/to/sample02"),
        sample_ids = c("sample01", "sample02"),
        processing = "raw",
        images = "lowres"
    )
    spe_list <- import(vlist)

    # --- Visium HD Import [Importing high-definition Visium HD data] ---
    # Key functions: TENxVisiumHD, import
    hd_vis <- TENxVisiumHD(
        spacerangerOut = "path/to/visium_hd_folder",
        images = "lowres",
        bin_size = "002",
        format = "h5"
    )
    spe_hd <- import(hd_vis)


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
        write.csv(as.data.frame(.main), "${prefix}_visiumio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_visiumio_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_visiumio_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_VISIUMIO:", paste0("    visiumio: ", as.character(packageVersion("VisiumIO")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visiumio_results.csv
    touch ${prefix}_visiumio_output.rds
    echo "BIOC_VISIUMIO:" > versions.yml
    echo "    visiumio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VISIUMIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VISIUMIO(ch_input)

    emit:
    results  = BIOC_VISIUMIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VISIUMIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VISIUMIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VISIUMIO.out.versions  // channel: path(versions.yml)
}
