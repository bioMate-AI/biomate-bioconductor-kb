#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BufferedMatrix
// A tabular style data object where most data is stored outside main memory. A buffer is used to speed
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BufferedMatrix/inst/doc/BufferedMatrix.R
// Upstream  : none
// Downstream: BufferedMatrixMethods
//
// Install: BiocManager::install("BufferedMatrix")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BUFFEREDMATRIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bufferedmatrix"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bufferedmatrix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bufferedmatrix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bufferedmatrix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("AddColumn", "ColMode", "Max", "Min", "ReadOnlyMode", "RowMode", "Sd", "Sum", "Var", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(AddColumn)
    library(ColMode)
    library(Max)
    library(Min)
    library(ReadOnlyMode)
    library(RowMode)
    library(Sd)
    library(Sum)
    library(Var)
    library(jsonlite)

    # --- Createbufferedmatrix [] ---
    # Key functions: createBufferedMatrix
    X <- createBufferedMatrix(10000)
    # --- Addcolumn [] ---
    # Key functions: AddColumn
    AddColumn(X)
    AddColumn(X)
    X
    # --- Createbufferedmatrix [] ---
    # Key functions: createBufferedMatrix
    X <- createBufferedMatrix(10000,2)
    # --- Usage [] ---
    # Key functions: usage, prefix, directory, RowMode, ColMode
    memory.usage(X)
    disk.usage(X)
    nrow(X)
    ncol(X)
    dim(X)
    # --- Readonlymode [] ---
    # Key functions: ReadOnlyMode
    ReadOnlyMode(X)
    is.ReadOnlyMode(X)
    ReadOnlyMode(X)
    is.ReadOnlyMode(X)
    # --- Createbufferedmatrix [] ---
    # Key functions: createBufferedMatrix
    X <- createBufferedMatrix(20,2)
    X[1:20,] <- 1:40
    B <- X[1:5,]
    B
    B[1:2,] <- B[1:2,]^2
    # --- Rep [] ---
    # Key functions: rep
    X[rep(c(TRUE,FALSE),10),1]
    # --- Subbufferedmatrix [] ---
    # Key functions: subBufferedMatrix
    Y <- subBufferedMatrix(X,1:5,1:2)
    Y
    # --- Createbufferedmatrix [] ---
    # Key functions: createBufferedMatrix, Max, Min, Sum, Var, Sd
    X <- createBufferedMatrix(10,3)
    X[1:10,] <- (1:30)^2
    Max(X)
    Min(X)
    mean(X)
    # --- Rowmeans [] ---
    # Key functions: rowMeans, colMeans, rowSums, colSums, rowVars, colVars, rowSd, colSd
    rowMeans(X)
    colMeans(X)
    rowSums(X)
    colSums(X)
    rowVars(X)
    # --- Function [] ---
    # Key functions: colApply
    sum.cube.root <- function(x){
    	sum(x^(1/3))
    }
    colApply(X,sum.cube.root)
    # --- Function [] ---
    # Key functions: rowApply
    sum.arbitrary.power <- function(x,power=2){
    	sum(x^power)
    }
    rowApply(X,sum.arbitrary.power,power=3)
    # --- Colapply [] ---
    # Key functions: colApply, is
    Y <- colApply(X,sort,decreasing=TRUE)
    is(Y,"BufferedMatrix")
    # --- Exp [] ---
    # Key functions: pow
    exp(X)
    log(X)
    sqrt(X)
    pow(X,2.0)
    # --- Function [] ---
    # Key functions: ewApply
    my.function <- function(x){
      x^2 +3*abs(x) - 9
    }
    ewApply(X, my.function)

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
        write.csv(as.data.frame(.main), "${prefix}_bufferedmatrix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_bufferedmatrix_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_bufferedmatrix_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUFFEREDMATRIX:", paste0("    bufferedmatrix: ", as.character(packageVersion("BufferedMatrix")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bufferedmatrix_results.csv
    touch ${prefix}_bufferedmatrix_output.rds
    echo "BIOC_BUFFEREDMATRIX:" > versions.yml
    echo "    bufferedmatrix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUFFEREDMATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUFFEREDMATRIX(ch_input)

    emit:
    results  = BIOC_BUFFEREDMATRIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUFFEREDMATRIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUFFEREDMATRIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUFFEREDMATRIX.out.versions  // channel: path(versions.yml)
}
