# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Category", "ALL", "hgu95av2.db", "annotate", "genefilter")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("Category")
library("ALL")
library("hgu95av2.db")
library("annotate")
library("genefilter")

data(ALL, package="ALL")

subsetType <- "BCR/ABL"
Bcell <- grep("^B", as.character(ALL$BT))
bcrAblOrNegIdx <- which(as.character(ALL$mol.biol) %in% c("NEG", subsetType))

bcrAblOrNeg <- ALL[, intersect(Bcell, bcrAblOrNegIdx)]
bcrAblOrNeg$mol.biol <- factor(bcrAblOrNeg$mol.biol)

save(bcrAblOrNeg, file="bcrAblOrNeg.RData")