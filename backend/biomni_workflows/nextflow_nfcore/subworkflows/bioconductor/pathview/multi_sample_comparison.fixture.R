# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pathview")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(pathview)

# Prepare gene expression data
data(gse16873.d)

# Prepare metabolite abundance data
sim.cpd.data <- sim.mol.data(mol.type="cpd", nmol=3000)
set.seed(10)
sim.cpd.data2 <- matrix(sample(sim.cpd.data, 18000, replace = TRUE), ncol = 6)
rownames(sim.cpd.data2) <- names(sim.cpd.data)
colnames(sim.cpd.data2) <- paste("exp", 1:6, sep = "")

# Write to TSV files
write.table(gse16873.d, file="multi_sample_gene_expression.tsv", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)
write.table(sim.cpd.data2, file="multi_sample_metabolite_abundance.tsv", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)