# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("IMMAN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(IMMAN)

data(FruitFly)
data(Celegance)

subFruitFly <- as.character(FruitFly$V1)[1:10]
subCelegance <- as.character(Celegance$V1)[1:10]

ProteinLists <- list(subFruitFly, subCelegance)

List1_Species_ID <- 7227
List2_Species_ID <- 6239

Species_IDs <- c(List1_Species_ID, List2_Species_ID)

saveRDS(ProteinLists, "ProteinLists.rds")
saveRDS(Species_IDs, "Species_IDs.rds")