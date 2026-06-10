# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PANR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PANR)

# Load and serialize Bakal2007
env_bakal <- new.env()
data("Bakal2007", package = "PANR", envir = env_bakal)
obj_bakal <- if ("Bakal2007" %in% ls(env_bakal)) {
    env_bakal$Bakal2007
} else {
    env_bakal[[ls(env_bakal)[1]]]
}
saveRDS(obj_bakal, "Bakal2007.rds")

# Load and serialize Bakal2007Cluster
env_cluster <- new.env()
data("Bakal2007Cluster", package = "PANR", envir = env_cluster)
obj_cluster <- if ("Bakal2007Cluster" %in% ls(env_cluster)) {
    env_cluster$Bakal2007Cluster
} else {
    env_cluster[[ls(env_cluster)[1]]]
}
saveRDS(obj_cluster, "Bakal2007Cluster.rds")