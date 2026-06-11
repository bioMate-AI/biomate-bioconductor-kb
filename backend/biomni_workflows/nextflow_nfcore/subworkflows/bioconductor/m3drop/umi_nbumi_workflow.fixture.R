# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("M3Drop", "M3DExampleData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(M3Drop)
library(M3DExampleData)

# Reproduce the vignette's data preparation for 'count_mat'
# This comes from chunk 7 of the vignette
count_mat <- NBumiConvertData(Mmus_example_list$data, is.counts=TRUE)

# Serialize 'count_mat' to the specified input file formats

# 1. Save as RDS
saveRDS(count_mat, "count_mat.rds")

# 2. Save as CSV (comma-separated, with row names, no quotes for numbers)
write.csv(count_mat, "count_mat.csv", row.names = TRUE, quote = FALSE)

# 3. Save as TSV (tab-separated, with row names, no quotes for numbers)
write.table(count_mat, "count_mat.tsv", sep = "\t", row.names = TRUE, quote = FALSE)