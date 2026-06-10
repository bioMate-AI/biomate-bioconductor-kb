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

# Reproduce the vignette's data-preparation code to materialize the example object.
# The vignette loads 'zimData' directly from the package's internal datasets.
data(zimData)

# Serialize the 'zimData' object to each declared input file in the exact format
# the workflow reads.

# 1. Save as 'zimData.csv'
# The workflow reads with: as.matrix(read.csv("zimData.csv", row.names = 1, check.names = FALSE))
# This requires row names to be written as the first column.
write.csv(zimData, "zimData.csv", row.names = TRUE)

# 2. Save as 'zimData.rds'
# The workflow reads with: readRDS("zimData.rds")
# This is a direct serialization of the R object.
saveRDS(zimData, "zimData.csv")

# 3. Save as 'zimData.txt'
# The workflow reads with: as.matrix(read.table("zimData.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
# This requires a tab-separated file with row names as the first column and column names in the header.
# Using col.names = NA ensures the top-left cell (for row names) is empty,
# which is the expected format when read.table is used with row.names = 1 and header = TRUE.
write.table(zimData, "zimData.csv", sep = "\t", row.names = TRUE, col.names = NA)