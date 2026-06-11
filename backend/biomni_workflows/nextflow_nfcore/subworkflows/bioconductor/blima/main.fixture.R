# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("blimaTestingData", "illuminaHumanv4.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(blimaTestingData)
library(illuminaHumanv4.db)

# 1. Reproduce blimatesting object
data(blimatesting)

# 2. Reproduce adrToIllumina object
adrToIllumina <- toTable(illuminaHumanv4ARRAYADDRESS)
adrToIllumina <- adrToIllumina[, c("ArrayAddress", "IlluminaID")]
colnames(adrToIllumina) <- c("Array_Address_Id", "Probe_Id")

# 3. Serialize objects to declared input files in the exact format
saveRDS(blimatesting, "blimatesting.rds")
saveRDS(adrToIllumina, "adrToIllumina.rds")