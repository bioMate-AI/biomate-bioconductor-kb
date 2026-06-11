# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cqn", "scales")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cqn)
library(scales)

# Reproduce the vignette's data-preparation code
data(montgomery.subset)
data(sizeFactors.subset)
data(uCovar)

# Prepare and serialize data for count_matrix.tsv
# The workflow reads this as a matrix. montgomery.subset is already a matrix.
# write.table will handle row.names and header correctly for the workflow's read.table call.
write.table(montgomery.subset, "count_matrix.tsv", sep = "\t", quote = FALSE, col.names = TRUE, row.names = TRUE)

# Prepare and serialize data for gene_lengths.tsv
# The workflow reads this as a data frame with row names and a column 'length'.
# uCovar contains 'length' as a column.
gene_lengths_df <- data.frame(length = uCovar$length, row.names = rownames(uCovar))
write.table(gene_lengths_df, "gene_lengths.tsv", sep = "\t", quote = FALSE, col.names = TRUE, row.names = TRUE)

# Prepare and serialize data for gc_content.tsv
# The workflow reads this as a data frame with row names and a column 'gccontent'.
# uCovar contains 'gccontent' as a column.
gc_content_df <- data.frame(gccontent = uCovar$gccontent, row.names = rownames(uCovar))
write.table(gc_content_df, "gc_content.tsv", sep = "\t", quote = FALSE, col.names = TRUE, row.names = TRUE)

# Prepare and serialize data for size_factors.tsv
# The workflow reads this as a data frame with row names and a column.
# sizeFactors.subset is a named numeric vector. Convert it to a data frame
# with sample names as row names and values in a column named 'sizeFactor'.
size_factors_df <- data.frame(sizeFactor = sizeFactors.subset, row.names = names(sizeFactors.subset))
write.table(size_factors_df, "size_factors.tsv", sep = "\t", quote = FALSE, col.names = TRUE, row.names = TRUE)

# Prepare and serialize data for sample_groups.tsv
# The vignette defines groups based on sample names and uses `rep(c("grp1", "grp2"), each = 5)`
# for the DGEList constructor, implying the first 5 samples are 'grp1' and the next 5 are 'grp2'.
# The sample order is given by colnames(montgomery.subset).
sample_names <- colnames(montgomery.subset)
group_assignments <- rep(c("grp1", "grp2"), each = 5)
sample_groups_df <- data.frame(group = group_assignments, row.names = sample_names)
write.table(sample_groups_df, "sample_groups.tsv", sep = "\t", quote = FALSE, col.names = TRUE, row.names = TRUE)