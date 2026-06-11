# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BLMA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BLMA)

# Load the 4 AML datasets as shown in the vignette
dataSets <- c("GSE17054", "GSE57194", "GSE33223", "GSE42140")
data(list = dataSets, package = "BLMA")

# Prepare dataList and groupList
names(dataSets) <- dataSets
dataList <- lapply(dataSets, function(dataset) get(paste0("data_", dataset)))
groupList <- lapply(dataSets, function(dataset) get(paste0("group_", dataset)))

# Serialize the objects to the working directory
saveRDS(data_GSE33223, "data_GSE33223.rds")
saveRDS(group_GSE33223, "group_GSE33223.rds")
saveRDS(dataList, "dataList.rds")
saveRDS(groupList, "groupList.rds")