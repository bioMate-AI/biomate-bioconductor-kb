# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("biomvRCNS", "TxDb.Hsapiens.UCSC.hg19.knownGene")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(biomvRCNS)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)

# 1. Reproduce the vignette's data-preparation code for encodeTP53.RData
# This loads an object named 'encodeTP53' into the environment.
data(encodeTP53, package='biomvRCNS')

# 2. Serialize the 'encodeTP53' object to 'encodeTP53.RData'
# The workflow uses load("encodeTP53.RData"), so save() is appropriate.
save(encodeTP53, file="encodeTP53.RData")

# 3. Reproduce the vignette's data-preparation code for Tx