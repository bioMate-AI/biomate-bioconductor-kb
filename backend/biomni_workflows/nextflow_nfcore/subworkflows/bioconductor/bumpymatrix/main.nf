#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BumpyMatrix
// Implements the BumpyMatrix class and several subclasses for holding non-scalar objects in each entry
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BumpyMatrix/inst/doc/BumpyMatrix.R
// Upstream  : BiocStyle, S4Vectors
// Downstream: alabaster.bumpy
//
// Install: BiocManager::install("BumpyMatrix")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BUMPYMATRIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bumpymatrix"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bumpymatrix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bumpymatrix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bumpymatrix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BumpyMatrix", "S4Vectors", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(BumpyMatrix)
    library(S4Vectors)
    library(jsonlite)

    # --- Matrix Creation [] ---
    # Key functions: splitAsBumpyMatrix
    df <- S4Vectors::DataFrame(
        x = rnorm(1000),
        y = rnorm(1000),
        gene = paste0("GENE_", sample(50, 1000, replace = TRUE)),
        cell = paste0("CELL_", sample(10, 1000, replace = TRUE))
    )
    mat <- splitAsBumpyMatrix(
        df[, c("x", "y")],
        row = df\$gene,
        column = df\$cell
    )
    smat <- splitAsBumpyMatrix(
        df[1:100, c("x", "y")],
        row = df\$gene[1:100],
        column = df\$cell[1:100],
        sparse = TRUE
    )

    # --- Statistical Summaries [] ---
    # Key functions: mean, var, quantile, range, pmax
    out_x <- mat[, , "x"]
    out_y <- mat[, , "y"]
    mean_x <- mean(out_x)
    var_x <- var(out_x)
    quant_x <- quantile(out_x)
    range_x <- range(out_x)
    pmax_xy <- pmax(out_x, out_y)


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
        write.csv(as.data.frame(.main), "${prefix}_bumpymatrix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_bumpymatrix_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_bumpymatrix_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUMPYMATRIX:", paste0("    bumpymatrix: ", as.character(packageVersion("BumpyMatrix")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bumpymatrix_results.csv
    touch ${prefix}_bumpymatrix_output.rds
    echo "BIOC_BUMPYMATRIX:" > versions.yml
    echo "    bumpymatrix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUMPYMATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUMPYMATRIX(ch_input)

    emit:
    results  = BIOC_BUMPYMATRIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUMPYMATRIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUMPYMATRIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUMPYMATRIX.out.versions  // channel: path(versions.yml)
}
