# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNAnorm")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNAnorm)

# Reproduce the vignette's data-preparation code
data(LS041)

# Serialize the LS041 object to the specified input files
# For 'LS041' and 'LS041.txt', use tab-separated format as read by read.table
write.table(LS041, file = "LS041.csv", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(LS041, file = "LS041.csv", sep = "\t", row.names = FALSE, quote = FALSE)

# For 'LS041.csv', use comma-separated format as read by read.csv
write.csv(LS041, file = "LS041.csv", row.names = FALSE, quote = FALSE)

# For 'LS041.tsv', use tab-separated format as read by read.delim
write.table(LS041, file = "LS041.csv", sep = "\t", row.names = FALSE, quote = FALSE)