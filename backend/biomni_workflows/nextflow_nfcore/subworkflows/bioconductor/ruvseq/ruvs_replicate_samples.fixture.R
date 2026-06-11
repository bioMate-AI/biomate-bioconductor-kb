# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RUVSeq", "zebrafishRNASeq", "EDASeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RUVSeq)
library(zebrafishRNASeq)
library(EDASeq) # newSeqExpressionSet is from EDASeq

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the example dataset
data(zfGenes)

# Filter out non-expressed genes (more than 5 reads in at least two samples)
filter <- apply(zfGenes, 1, function(x) length(x[x>5])>=2)
filtered <- zfGenes[filter,]

# Create the sample group factor
x <- as.factor(rep(c("Ctl", "Trt"), each=3))

# Store the data in a SeqExpressionSet object
# The phenoData is a data.frame with sample names as row names and 'x' as a column
set <- newSeqExpressionSet(as.matrix(filtered), phenoData = data.frame(x, row.names=colnames(filtered)))

# 2. Serialize the object to EACH declared input file in the EXACT format the workflow reads

# Extract the counts matrix
counts_matrix <- counts(set)

# Extract the sample information (phenoData)
sample_info_df <- pData(set)

# Write counts_matrix.csv
# The workflow reads with `row.names = 1`, so we write row names as the first column.
# `check.names = FALSE` in read.csv means column names are taken as-is, which is default for write.csv.
write.csv(counts_matrix, "counts_matrix.csv", row.names = TRUE, quote = FALSE)

# Write sample_groups.csv
# The workflow reads with `check.names = FALSE` but *without* `row.names = 1`.
# This implies the first column of the CSV should be a regular data column, not row names.
# To achieve this, we explicitly create a 'SampleID' column from the row names of sample_info_df
# and then write the CSV without R'