# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("baySeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(baySeq)

# Reproduce the vignette's data-preparation code for 'pairData'
# From vignette chunk 13: data(pairData)
data(pairData)

# Serialize the 'pairData' object to each declared input file format

# 1. pairData.csv (read by as.matrix(read.csv("pairData.csv", row.names = 1)))
# write.csv handles row names and headers appropriately for this read function.
# quote = FALSE is used as the data is numeric and quoting is not needed.
write.csv(pairData, "pairData.csv", row.names = TRUE, quote = FALSE)

# 2. pairData.tsv (read by as.matrix(read.delim("pairData.tsv", row.names = 1)))
# read.delim is a wrapper for read.table with sep = "\t".
# col.names = NA ensures the header row has an empty string for the row name column,
# which is necessary for read.table/read.delim with header = TRUE and row.names = 1.
write.table(pairData, "pairData.csv", sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)

# 3. pairData.txt (read by as.matrix(read.table("pairData.txt", header = TRUE, row.names = 1)))
# Similar to .tsv, using write.table with sep = "\t" (common for .txt data files).
write.table(pairData, "pairData.csv", sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)

# 4. pairData.rds (read by readRDS("pairData.rds"))
saveRDS(pairData, "pairData.csv")

# 5. pairData (no extension) (read by as.matrix(read.table("pairData", header = TRUE, row.names = 1)))
# This assumes it's a text file, similar to .txt or .tsv, based on the read.table call.
write.table(pairData, "pairData.csv", sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)