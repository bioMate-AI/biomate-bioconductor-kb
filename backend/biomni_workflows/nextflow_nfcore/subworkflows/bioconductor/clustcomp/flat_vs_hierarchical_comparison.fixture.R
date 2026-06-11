# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Biobase", "colonCA", "clustComp")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Biobase)
library(colonCA)
data(colonCA)

rownames(colonCA)[39:42] <- paste("HSAC07", 0:3)
rownames(colonCA)[50:53] <- paste("UMGAP", 0:3)
rownames(colonCA)[260:263] <- paste("i", 0:3)

library(clustComp)

set.seed(0)
# seven flat clusters:
flat1 <- paste("A", kmeans(exprs(colonCA), 7)$cluster, sep = "")
# dendrograms with 2000 leaves:
hierar <- hclust(dist(exprs(colonCA)))

# The workflow reads 'expression_matrix' as a matrix.
# The vignette uses exprs(colonCA) as the expression matrix.
expression_matrix <- exprs(colonCA)

# Serialize hierar as an RDS file
saveRDS(hierar, "hierar")

# Serialize flat1 as a plain text file, one element per line
writeLines(flat1, "flat1")

# Serialize expression_matrix as a tab-separated file with header and row names
write.table(expression_matrix, "expression_matrix", sep = "\t", quote = FALSE, col.names = NA)