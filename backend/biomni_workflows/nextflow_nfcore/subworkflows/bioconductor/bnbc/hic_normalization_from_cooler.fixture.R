# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bnbc", "BSgenome.Hsapiens.UCSC.hg19", "S4Vectors")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bnbc)
library(BSgenome.Hsapiens.UCSC.hg19)
library(S4Vectors) # For DataFrame object used by colData

# 1. Prepare hg19 object and save to hg19.rds
# The vignette uses BSgenome.Hsapiens.UCSC.hg19 directly.
hg19_obj <- BSgenome.Hsapiens.UCSC.hg19
saveRDS(hg19_obj, "hg19.rds")

# 2. Load cgEx, the example ContactGroup object, which contains the colData.
# The vignette explicitly states: "An example dataset for chromosome 22 is supplied with the package. data(cgEx)"
data(cgEx)

# 3. Prepare colData object and save to colData.rds
# The workflow reads "colData.rds" or "colData.csv".
# The vignette uses colData(cgEx) for various operations.
colData_obj <- colData(cgEx)
saveRDS