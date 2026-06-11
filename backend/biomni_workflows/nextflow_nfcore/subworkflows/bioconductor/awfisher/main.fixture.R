# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AWFisher", "limma")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AWFisher)
library(limma)

# Load the example data
data(data_mouseMetabolism)
dataExp <- data_mouseMetabolism

# Initialize the p-value matrix
pmatrix <- matrix(0, nrow = nrow(dataExp[[1]]), ncol = length(dataExp))
rownames(pmatrix) <- rownames(dataExp[[1]])
colnames(pmatrix) <- names(dataExp)

# Populate the p-value matrix by performing differential expression analysis in each study
for (s in 1:length(dataExp)) {
  adata <- dataExp[[s]]
  ControlLabel = grep('wt', colnames(adata))
  caseLabel = grep('LCAD', colnames(adata))
  label <- rep(NA, ncol(adata))
  label[ControlLabel] = 0
  label[caseLabel] = 1

  design = model.matrix(~label)
  fit <- lmFit(adata, design)
  fit <- eBayes(fit)

  pmatrix[, s] <- fit$p.value[, 2]
}

# Serialize the pmatrix object to the required input file formats

# 1. Save as pmatrix.csv
# The workflow reads with `read.csv(..., row.names = 1)`, so we need to write row names.
write.csv(pmatrix, "pmatrix.csv", row.names = TRUE)

# 2. Save as pmatrix.tsv
# The workflow reads with `read.delim(..., row.names = 1)`, so we need to write row names.
# Use tab separator and no quoting for TSV.
write.table(pmatrix, "pmatrix.csv", sep = "\t", row.names = TRUE, quote = FALSE)

# 3. Save as pmatrix.rds
# The workflow reads with `readRDS(...)`.
saveRDS(pmatrix, "pmatrix.csv")

# 4. Save as pmatrix (plain file, typically tab-separated for read.table)
# The workflow reads with `read.table(..., header = TRUE, row.names = 1)`.
# Use tab separator and no quoting.
write.table(pmatrix, "pmatrix.csv", sep = "\t", row.names = TRUE, quote = FALSE)