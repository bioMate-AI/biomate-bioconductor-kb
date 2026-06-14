# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Rmagpie")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Rmagpie)
data("vV70genesDataset")
.obj <- get("vV70genesDataset")
saveRDS(.obj, "ExpressionSet.rds")

# The workflow also requires "vV_newSamples.txt" (new-sample expression table passed to
# classifyNewSamples()). Rmagpie ships it in extdata; copy the real file, else synthesise a
# tab-delimited genes x samples table from the ExpressionSet so classifyNewSamples() runs.
.ns <- list.files(system.file("extdata", package="Rmagpie"),
                  pattern="vV_newSamples\\.txt$", recursive=TRUE, full.names=TRUE)
if (length(.ns)) {
  file.copy(.ns[[1]], "vV_newSamples.txt", overwrite=TRUE)
} else {
  .e <- Biobase::exprs(.obj)
  .new <- .e[, seq_len(min(5L, ncol(.e))), drop=FALSE]
  colnames(.new) <- paste0("new", seq_len(ncol(.new)))
  write.table(.new, "vV_newSamples.txt", sep="\t", quote=FALSE, col.names=NA)
}
