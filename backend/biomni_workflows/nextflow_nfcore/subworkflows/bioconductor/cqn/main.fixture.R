# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cqn", "scales")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cqn)
library(scales) # Used in vignette, though not strictly for data generation

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data(montgomery.subset)
data(sizeFactors.subset)
data(uCovar)

# Ensure data consistency as checked in the vignette
stopifnot(all(rownames(montgomery.subset) == rownames(uCovar)))
stopifnot(colnames(montgomery.subset) == names(sizeFactors.subset))

# 2. Serialize objects to declared input files in the exact format the workflow reads

# count_matrix.tsv
# Workflow reads: counts <- as.matrix(read.delim("count_matrix.tsv", row.names = 1, header = TRUE, check.names = FALSE))
# `montgomery.subset` is already a matrix.
write.table(montgomery.subset, "count_matrix.tsv",
            sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)

# gene_lengths.tsv
# Workflow reads: gene_lengths_raw <- read.delim("gene_lengths.tsv", row.names = 1, header = TRUE, check.names = FALSE)
# Create a data frame with gene IDs as row names and 'length' as a column.
gene_lengths_df <- data.frame(length = uCovar$length, row.names = rownames(uCovar))
write.table(gene_lengths_df, "gene_lengths.tsv",
            sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)

# gc_content.tsv
# Workflow reads: gc_content_raw <- read.delim("gc_content.tsv", row.names = 1, header = TRUE, check.names = FALSE)
# Create a data frame with gene IDs as row names and 'gccontent' as a column.
gc_content_df <- data.frame(gccontent = uCovar$gccontent, row.names = rownames(uCovar))
write.table(gc_content_df, "gc_content.tsv",
            sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)

# size_factors.tsv
# Workflow reads: size_factors_raw <- read.delim("size_factors.tsv", row.names = 1, header = TRUE, check.names = FALSE)
# Create a data frame with sample IDs as row names and 'size_factor' as a column.
size_factors_df <- data.frame(size_factor = sizeFactors.subset, row.names = names(sizeFactors.subset))
write.table(size_factors_df, "size_factors.tsv",
            sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)