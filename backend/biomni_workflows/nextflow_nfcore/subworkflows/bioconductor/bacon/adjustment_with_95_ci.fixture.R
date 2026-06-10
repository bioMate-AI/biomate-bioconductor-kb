# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bacon")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bacon)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# A vector containing 5000 z-scores is generated from a normal mixture distribution.
y <- rnormmix(5000, c(0.9, 0.2, 1.3, 1, 4, 1))

# As described in section "5 Adjustment with 95% CI":
# "Given a vector of z-scores. Replicate the z-scores, minimal 30 times, and store in a matrix. zs <"
# We will replicate 'y' 30 times to create the 'zs' matrix.
num_replicates <- 30
zs <- replicate(num_replicates, y)

# Add row and column names as expected by read.csv/read.table with row.names=1
rownames(zs) <- paste0("feature_", 1:nrow(zs))
colnames(zs) <- paste0("sample_", 1:ncol(zs))

# 2. Serialize that object to EACH declared input file (zs, zs.csv, zs.tsv)
# The workflow reads 'zs' first as CSV, then as a generic table.
# To satisfy 'read.csv("zs", ...)', we save 'zs' as a CSV file.
write.csv(zs, "zs.csv", row.names = TRUE)

# To satisfy 'read.csv("zs.csv", ...)', we save 'zs' as a CSV file.
write.csv(zs, "zs.csv", row.names = TRUE)

# To satisfy 'read.delim("zs.tsv", ...)', we save 'zs' as a TSV file.
write.table(zs, "zs.csv", sep = "\t", row.names = TRUE, quote = FALSE)