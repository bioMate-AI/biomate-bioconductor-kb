# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ALL", "org.Hs.eg.db", "GOstats")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("ALL")
library("org.Hs.eg.db")
library("GOstats")

# Prepare ExpressionSet object
data(ALL, package="ALL")
subsetType <- "ALL1/AF4"
Bcell <- grep("^B", as.character(ALL$BT))
bcrAblOrNegIdx <- which(as.character(ALL$mol) %in% c("NEG", subsetType))
bcrAblOrNeg <- ALL[, intersect(Bcell, bcrAblOrNegIdx)]
bcrAblOrNeg$mol.biol = factor(bcrAblOrNeg$mol.biol)

expression_data <- bcrAblOrNeg
save(expression_data, file="expression_data.RData")

# Prepare selected genes list
universe <- Lkeys(org.Hs.egGO)
genes <- universe[1:500]

write.table(genes, file="selected_genes.txt", row.names=FALSE, col.names=FALSE, quote=FALSE)