# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("compEpiTools", "TxDb.Mmusculus.UCSC.mm9.knownGene", "org.Mm.eg.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(compEpiTools)
require(TxDb.Mmusculus.UCSC.mm9.knownGene)
require(org.Mm.eg.db)

# Recreate txdb object as in the vignette
txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene

# Recreate TSSpos object as in the vignette
TSSpos <- TSS(txdb)

# Recreate 'gr' object for user_regions.RData as in the vignette's GRheat1 section
gr <- TSSpos[1:50]
start(gr) <- start(gr) - 1000
end(gr) <- end(gr) - 600

# Save 'gr' object to user_regions.RData
save(gr, file = "user_regions.RData")

# Recreate 'pvalues' object for pvalues.txt as in the vignette's GRheat1 section
pvalues <- c(runif(20,1e-20,1e-8), runif(15,1e-4,1e-2), runif(15,0.5,1))
pvalues <- cbind(pvalues, rep(0, 50), rep(0, 50))

# Save 'pvalues' object to pvalues.txt in the format expected by read.table(..., header = FALSE)
write.table(pvalues, file = "pvalues.txt", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)