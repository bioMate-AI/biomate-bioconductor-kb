# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BUS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BUS)

# Reproduce data preparation from vignette chunk 'association.genes.traits'
data(tumors.mRNA)
exp <- as.matrix(tumors.mRNA)[11:15,]
rownames(exp) <- rownames(tumors.mRNA)[11:15]

data(tumors.miRNA)
trait <- as.matrix(tumors.miRNA)[11:15,]
rownames(trait) <- rownames(tumors.miRNA)[11:15]

# Serialize objects to CSV files in the format the workflow expects
write.csv(exp, "expression_matrix.csv", row.names = TRUE)
write.csv(trait, "trait_matrix.csv", row.names = TRUE)