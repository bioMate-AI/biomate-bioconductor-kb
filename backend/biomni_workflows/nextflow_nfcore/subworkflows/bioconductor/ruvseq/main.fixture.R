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
library(EDASeq) # Required for newSeqExpressionSet and betweenLaneNormalization

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load raw RNA-Seq read counts
data(zfGenes)

# Filter out non-expressed genes, by requiring more than 5 reads in at least two samples for each gene.
filter <- apply(zfGenes, 1, function(x) length(x[x>5])>=2)
filtered <- zfGenes[filter,]

# Identify ERCC spike-ins (control genes) from the filtered data
spikes <- rownames(filtered)[grep("^ERCC", rownames(filtered))]

# The workflow reads the original, unfiltered counts matrix.
# The workflow reads the list of control genes (spikes).

# 2. Serialize objects to declared input files

# Save the raw counts matrix to counts_matrix.csv
# The workflow reads with row.names = 1, so we write with row.names = TRUE
write.csv(zfGenes, "counts_matrix.csv", row.names = TRUE)

# Save the control gene names to control_genes.txt
# The workflow reads with readLines, so we write with writeLines
writeLines(spikes, "control_genes.txt")