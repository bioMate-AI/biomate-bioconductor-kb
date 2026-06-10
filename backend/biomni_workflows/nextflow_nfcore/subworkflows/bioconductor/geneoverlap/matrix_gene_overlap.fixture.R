# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GeneOverlap")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GeneOverlap)

# Reproduce the vignette's data preparation
data(GeneOverlap)

# Serialize the objects to the specified input files
saveRDS(hESC.ChIPSeq.list, "set1.rds")
saveRDS(hESC.RNASeq.list, "set2.rds")

# The workflow reads background_size as a plain text file for the primary branch
# Write the integer value of gs.RNASeq to "background_size"
writeLines(as.character(gs.RNASeq), "background_size")