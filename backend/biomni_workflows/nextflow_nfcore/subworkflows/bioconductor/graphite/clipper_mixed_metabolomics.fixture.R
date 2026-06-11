# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("graphite", "ALL", "a4Preproc")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(graphite)
library(ALL)
library(a4Preproc)

# Reproduce the vignette's data preparation for gene expression
data(ALL)
pheno <- as(phenoData(ALL), "data.frame")
samples <- unlist(lapply(c("NEG", "BCR/ABL"), function(t) {
  which(grepl("^B\\d*", pheno$BT) & (pheno$mol.biol == t))[1:10]
}))

expr <- exprs(ALL)[,samples]
rownames(expr) <- paste("ENTREZID",
                        featureData(addGeneInfo(ALL))$ENTREZID,
                        sep = ":")

# Write the gene expression matrix
write.table(expr, "Terunuma_gene_expr.txt", sep = "\t", quote = FALSE, col.names = NA)

# Create a metabolite abundance matrix using the same samples and CHEBI IDs from the vignette
metabolite_expr <- expr[1:2, ]
rownames(metabolite_expr) <- c("CHEBI:77750", "CHEBI:15351")

# Write the metabolite expression matrix
write.table(metabolite_expr, "Terunuma_metabolite_expr.txt", sep = "\t", quote = FALSE, col.names = NA)