# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("edge")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(edge)

# Reproduce the vignette's data preparation for the 'gibson' dataset
data(gibson)
gibexpr <- gibson$gibexpr
gender <- gibson$gender
batch <- gibson$batch
location <- gibson$location

# Serialize the objects to files using saveRDS, as read_input prioritizes readRDS
saveRDS(gibexpr, "gibexpr")
saveRDS(gender, "gender")
saveRDS(batch, "batch")
saveRDS(location, "location")