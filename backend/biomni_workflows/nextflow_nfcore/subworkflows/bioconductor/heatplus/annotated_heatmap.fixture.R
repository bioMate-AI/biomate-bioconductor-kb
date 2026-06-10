# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Biobase", "limma")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Biobase)
library(limma)

# Reproduce the vignette's data-preparation code to materialize the example object
# From vignette chunk 2:
data(sample.ExpressionSet)
exdat = sample.ExpressionSet

# From vignette chunk 3:
design1 = model.matrix( ~ type, data=pData(exdat))
lm1 = lmFit(exprs(exdat), design1)
lm1 = eBayes(lm1)
geneID = rownames(topTable(lm1, coef=2, num=100, adjust="none",
	p.value=0.05))

# From vignette chunk 4:
exdat2 = exdat[geneID,]

# Extract the expression matrix and sample metadata
# The workflow uses exprs(exdat2) and pData(exdat2) in its examples (e.g., chunk 10)
exprs_matrix_data <- exprs(exdat2)
sample_metadata_data <- pData(exdat2)

# Serialize the data to CSV files in the exact format the workflow reads
# The workflow reads with row.names = 1, check.names = FALSE.
# This means we should write with row.names = TRUE and ensure column names are preserved.
write.csv(exprs_matrix_data, "exprs_matrix.csv", row.names = TRUE, quote = FALSE)
write.csv(sample_metadata_data, "sample_metadata.csv", row.names = TRUE, quote = FALSE)