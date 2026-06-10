# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("blacksheepr", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(blacksheepr)
library(SummarizedExperiment)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data("sample_phosphodata")
phosphotable <- sample_phosphodata

data("sample_annotationdata")
comptable <- sample_annotationdata

# 2. Serialize that object to EACH declared input file in the EXACT format the workflow reads

# For raw_counts.tsv:
# The workflow reads: cts <- as.matrix(read.csv(raw_counts_file, sep = "\t", row.names = "gene_id", check.names = FALSE))
# This requires a tab-separated file where one column is explicitly named "gene_id" and contains the row identifiers.
# phosphotable has row names that are the feature identifiers.
# Convert phosphotable matrix to a data frame, add a 'gene_id' column from its row names, then write.
raw_counts_df <- as.data.frame(phosphotable)
raw_counts_df <- cbind(gene_id = rownames(raw_counts_df), raw_counts_df)
write.table(raw_counts_df, "raw_counts.tsv", sep = "\t", row.names = FALSE, quote = FALSE)

# For multiclass_annotations.csv:
# The workflow reads: dummyannotations <- read.csv(annotations_file, row.names = 1, check.names = FALSE)
# This requires a comma-separated file where the first column serves as row names.
# comptable already has sample IDs as row names.
write.csv(comptable, "multiclass_annotations.csv", row.names = TRUE, quote = FALSE)