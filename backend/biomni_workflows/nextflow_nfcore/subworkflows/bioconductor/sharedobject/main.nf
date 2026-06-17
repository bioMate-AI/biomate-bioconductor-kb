#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SharedObject
// This package is developed for facilitating parallel computing in R. It is capable to create an R obj
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/SharedObject/inst/doc/quick_start_guide.html
// Upstream  : parallel
// Downstream: none
//
// Install: BiocManager::install("SharedObject")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_SHAREDOBJECT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sharedobject"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sharedobject_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sharedobject_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sharedobject_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SharedObject", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(SharedObject)
    library(jsonlite)

    # --- Create Shared Objects [] ---
    # Key functions: share, is.shared
    A1 <- matrix(1:9, 3, 3)
    A2 <- share(A1)
    status_A1 <- is.shared(A1)
    status_A2 <- is.shared(A2)
    x1 <- list(A = 1:3, B = as.symbol("x"))
    shared_x <- share(x1)
    is_shared_list <- is.shared(shared_x)

    # --- Configure Shared Object Options [] ---
    # Key functions: sharedObjectPkgOptions
    opts <- sharedObjectPkgOptions()
    sharedObjectPkgOptions(mustWork = TRUE)
    new_opts <- sharedObjectPkgOptions()
    sharedObjectPkgOptions(mustWork = FALSE)

    # --- Parallel Processing with Shared Objects [] ---
    # Key functions: share, is.shared
    large_vec <- share(rep(0, 10000))
    cl <- parallel::makeCluster(2)
    parallel::clusterExport(cl, "large_vec")
    results <- parallel::clusterEvalQ(cl, {
        SharedObject::is.shared(large_vec)
    })
    parallel::stopCluster(cl)

    # --- Manage Shared Memory [] ---
    # Key functions: share, is.shared, listSharedObjects
    x1 <- share(1:4, copyOnWrite = FALSE)
    x2 <- x1
    x2[1] <- 0L
    shared_status <- is.shared(x2)
    shared_list <- listSharedObjects()


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
        write.csv(as.data.frame(.main), "${prefix}_sharedobject_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_sharedobject_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_sharedobject_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SHAREDOBJECT:", paste0("    sharedobject: ", as.character(packageVersion("SharedObject")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sharedobject_results.csv
    touch ${prefix}_sharedobject_output.rds
    echo "BIOC_SHAREDOBJECT:" > versions.yml
    echo "    sharedobject: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SHAREDOBJECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SHAREDOBJECT(ch_input)

    emit:
    results  = BIOC_SHAREDOBJECT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SHAREDOBJECT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SHAREDOBJECT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SHAREDOBJECT.out.versions  // channel: path(versions.yml)
}
