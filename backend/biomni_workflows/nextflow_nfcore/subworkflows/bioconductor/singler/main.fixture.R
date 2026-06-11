# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleR", "celldex", "scRNAseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SingleR)
library(celldex)
library(scRNAseq)

# Prepare the reference dataset as per the vignette
hpca.se <- HumanPrimaryCellAtlasData()
saveRDS(hpca.se, "reference_dataset.rds")

# Prepare the test dataset as per the vignette
hESCs <- LaMannoBrainData('human-es')
hESCs <- hESCs[, 1:100]
saveRDS(hESCs, "test_dataset.rds")