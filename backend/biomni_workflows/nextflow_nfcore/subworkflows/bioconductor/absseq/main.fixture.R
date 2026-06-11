# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ABSSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ABSSeq)

# Reproduce the vignette's data preparation
data(simuN5)

# Prepare counts.tsv
# The workflow reads counts.tsv as a matrix with row names from the first column.
# write.table with row.names = TRUE and col.names = NA ensures this format.
write.table(simuN5$counts, "counts.tsv", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)

# Prepare groups.csv
# The workflow reads groups.csv as a data frame.
# Create a data frame from simuN5$groups and write it without row names.
groups_df <- data.frame(group = simuN5$groups)
write.csv(groups_df, "groups.csv", quote = FALSE, row.names = FALSE)