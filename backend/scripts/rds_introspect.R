#!/usr/bin/env Rscript
# Best-effort introspection of .rds outputs -> <name>.rds.json sidecars, so the after-run
# UI can preview an R object (class, dims, assays, reductions, colData) inline instead of
# showing an opaque "Open in RStudio" blob.
#
# Two ways to use it:
#   1. Standalone:  Rscript rds_introspect.R [file1.rds file2.rds ...]   (default: *.rds in cwd)
#   2. As an epilogue appended to each Bioconductor workflow's R script (recommended, because
#      the executor disables publishDir and CRT-S3 on the head JVM — a separate Nextflow
#      process is not a safe way to emit these). When used as an epilogue, also add
#      `path("*.rds.json"), emit: summaries, optional: true` to the process output block so
#      Nextflow collects the sidecars like any other output. The body below is self-contained
#      and never throws (tryCatch around every object), so it cannot fail the workflow.
suppressWarnings(suppressMessages({
  .args  <- commandArgs(trailingOnly = TRUE)
  .files <- if (length(.args)) .args else Sys.glob("*.rds")
  for (.f in .files) {
    .info <- tryCatch({
      .obj <- readRDS(.f)
      .i <- list(class = class(.obj))
      .d <- tryCatch(dim(.obj), error = function(e) NULL)
      if (!is.null(.d)) .i$dim <- as.integer(.d) else .i$length <- length(.obj)
      if (requireNamespace("SummarizedExperiment", quietly = TRUE) &&
          methods::is(.obj, "SummarizedExperiment")) {
        .i$assays  <- tryCatch(SummarizedExperiment::assayNames(.obj), error = function(e) NULL)
        .i$colData <- tryCatch(colnames(SummarizedExperiment::colData(.obj)), error = function(e) NULL)
        .i$rowData <- tryCatch(colnames(SummarizedExperiment::rowData(.obj)), error = function(e) NULL)
      }
      if (requireNamespace("SingleCellExperiment", quietly = TRUE) &&
          methods::is(.obj, "SingleCellExperiment")) {
        .i$reducedDims <- tryCatch(SingleCellExperiment::reducedDimNames(.obj), error = function(e) NULL)
      }
      if (is.list(.obj) && !is.null(names(.obj))) .i$names <- names(.obj)
      .i$summary <- paste0(class(.obj)[1],
        if (!is.null(.d)) sprintf(": %s rows x %s cols", .d[1], .d[2]) else "")
      .i
    }, error = function(e) list(class = "(unreadable)", summary = conditionMessage(e)))
    tryCatch(
      writeLines(jsonlite::toJSON(.info, auto_unbox = TRUE, null = "null"), paste0(.f, ".json")),
      error = function(e) NULL)
  }
}))
