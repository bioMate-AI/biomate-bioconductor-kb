# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("EBSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(EBSeq)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load GeneMat from the EBSeq package as shown in vignette chunk 2
data(GeneMat)

# Create the Conditions vector as used in vignette chunk 4 for the EBTest call
# Conditions=as.factor(rep(c("C1","C2"),each=5))
Conditions <- as.factor(rep(c("C1","C2"),each=5))

# 2. Serialize objects to declared input files

# For gene_counts.csv:
# The workflow reads: GeneMat <- as.matrix(read.csv("gene_counts.csv", row.names = 1, check.names = FALSE))
# This implies the first column of the CSV should be row names.
# write.csv will handle matrix input correctly.
write.csv(GeneMat, "gene_counts.csv", row.names = TRUE, quote = FALSE)

# For sample_conditions.csv:
# The workflow reads: cond_raw <- read.csv("sample_conditions.csv", header = FALSE, stringsAsFactors = FALSE)
# This implies the file should have no header and contain the conditions as a single column.
# Wrap Conditions in a data.frame to ensure it's written as a single column.
write.csv(data.frame(Conditions), "sample_conditions.csv", row.names = FALSE, col.names = FALSE, quote = FALSE)