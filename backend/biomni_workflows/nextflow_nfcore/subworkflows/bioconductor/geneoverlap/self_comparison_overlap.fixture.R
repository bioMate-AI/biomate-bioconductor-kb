# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GeneOverlap")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GeneOverlap)
data(GeneOverlap)

# The workflow reads 'set1' from "set1.rds".
# We'll use hESC.ChIPSeq.list$H3K4me3 as an example gene list for 'set1'.
saveRDS(hESC.ChIPSeq.list$H3K4me3, "set1.rds")

# The workflow reads 'val' from "background_size".
# The vignette uses gs.RNASeq for genome.size.
saveRDS(gs.RNASeq, "background_size")