# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cellity")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cellity)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code to materialize the example objects.

# Load sample counts data from the package
data(sample_counts)

# Load sample statistics data from the package
data(sample_stats)

# Load training features data from the package
data(training_mES_features)

# Load training labels data from the package
data(training_mES_labels)

# Load hyperparameters data from the package
data(param_mES_all)

# 2. Serialize objects to declared input files in the exact format the workflow reads.

# Save sample_counts to gene_counts.tsv
# The workflow reads with read.delim(..., row.names = 1), so write row names as the first column.
write.table(sample_counts, "gene_counts.tsv", sep = "\t", quote = FALSE, col.names = NA)

# Save sample_stats to read_stats.tsv
# The workflow reads with read.delim(..., row.names = 1), so write row names as the first column.
write.table(sample_stats, "read_stats.tsv", sep = "\t", quote = FALSE, col.names = NA)

# Save training_mES_features to training_features.RData
# The workflow loads this RData file, expecting the object 'training_mES_features' to be present.
save(training_mES_features, file = "training_features.RData")

# Save training_mES_labels to training_labels.RData
# The workflow loads this RData file, expecting the object 'training_mES_labels' to be present.
save(training_mES_labels, file = "training_labels.RData")

# Save param_mES_all to hyperparameters.RData
# The workflow loads this RData file, expecting the object 'param_mES_all' to be present.
save(param_mES_all, file = "hyperparameters.RData")