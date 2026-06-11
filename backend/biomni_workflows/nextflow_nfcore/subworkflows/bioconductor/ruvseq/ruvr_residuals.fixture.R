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

# Reproduce the vignette's data preparation
data(zfGenes)

filter <- apply(zfGenes, 1, function(x) length(x[x>5])>=2)
filtered <- zfGenes[filter,]
genes <- rownames(filtered)[grep("^ENS", rownames(filtered))]
spikes <- rownames(filtered)[grep("^ERCC", rownames(filtered))]

x <- as.factor(rep(c("Ctl", "Trt"), each=3))
set <- newSeqExpressionSet(as.matrix(filtered), phenoData = data.frame(x, row.names=colnames(filtered)))

set <- betweenLaneNormalization(set, which="upper")

set1 <- RUVg(set, spikes, k=1)

# Extract counts data and sample groups
counts_data <- counts(set1)
sample_groups <- pData(set1)

# Serialize to CSV files
write.csv(counts_data, "counts_matrix.csv", row.names = TRUE, quote = FALSE)
write.csv(sample_groups, "sample_groups.csv", row.names = TRUE, quote = FALSE)