#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ResidualMatrix
// Provides delayed computation of a matrix of residuals after fitting a linear model to each column of
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ResidualMatrix/inst/doc/ResidualMatrix.R
// Upstream  : Matrix
// Downstream: none
//
// Install: BiocManager::install("ResidualMatrix")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_RESIDUALMATRIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-residualmatrix"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_residualmatrix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_residualmatrix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_residualmatrix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ResidualMatrix", "jsonlite", "Matrix")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(ResidualMatrix)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: gl, rsparsematrix, ResidualMatrix
    ---------------------------------------------------------------------
    design <- model.matrix(~gl(5, 10000))
    # Making up a large-ish sparse matrix.
    library(Matrix)
    set.seed(100)
    # --- Hist [] ---
    # Key functions: rowSums
    ---------------------------------------------------------------------
    hist(rowSums(resids))
    # --- Matrix [] ---
    # Key functions: gl, runif
    ---------------------------------------------------------------------
    design2 <- model.matrix(~gl(2, 10000))
    design2 <- cbind(design2, BAD=runif(nrow(design2)))
    colnames(design2)
    # --- Rsparsematrix [] ---
    # Key functions: rsparsematrix, ResidualMatrix
    ---------------------------------------------------------------------
    # Making up another large-ish sparse matrix.
    y0 <- rsparsematrix(nrow(design2), 30000, 0.01)
    resid2 <- ResidualMatrix(y0, design2, keep=1:2)
    resid2
    # --- Gl [] ---
    # Key functions: gl, rnorm, ResidualMatrix
    ---------------------------------------------------------------------
    batches <- gl(3, 1000)
    controls <- c(1:100, 1:100+1000, 1:100+2000)
    y <- matrix(rnorm(30000), nrow=3000)
    resid3 <- ResidualMatrix(y, design=model.matrix(~batches), restrict=controls)

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
        write.csv(as.data.frame(.main), "${prefix}_residualmatrix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_residualmatrix_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_residualmatrix_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RESIDUALMATRIX:", paste0("    residualmatrix: ", as.character(packageVersion("ResidualMatrix")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_residualmatrix_results.csv
    touch ${prefix}_residualmatrix_output.rds
    echo "BIOC_RESIDUALMATRIX:" > versions.yml
    echo "    residualmatrix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RESIDUALMATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RESIDUALMATRIX(ch_input)

    emit:
    results  = BIOC_RESIDUALMATRIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RESIDUALMATRIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RESIDUALMATRIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RESIDUALMATRIX.out.versions  // channel: path(versions.yml)
}
