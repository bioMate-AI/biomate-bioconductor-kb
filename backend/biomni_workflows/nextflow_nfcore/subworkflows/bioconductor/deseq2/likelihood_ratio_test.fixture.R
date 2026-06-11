# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DESeq2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DESeq2)

# Create synthetic count data and coldata matching the vignette's Quick Start
set.seed(1)
cts <- matrix(rnbinom(1000, mu=100, size=1/0.1), ncol=10)
coldata <- data.frame(
  batch = factor(rep(c("B1", "B2"), 5)),
  condition = factor(rep(c("trt", "untrt"), each=5))
)
rownames(coldata) <- paste0("sample", 1:10)
colnames(cts) <- rownames(coldata)

# Construct the DESeqDataSet object as shown in the vignette
dds <- DESeqDataSetFromMatrix(
  countData = cts,
  colData = coldata,
  design = ~ batch + condition
)

# Save the object to the expected input file
saveRDS(dds, "dds.rds")