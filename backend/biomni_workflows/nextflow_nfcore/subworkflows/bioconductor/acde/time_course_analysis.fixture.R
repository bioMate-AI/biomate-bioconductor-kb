# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("acde")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(acde)

# Reproduce the 'phytophthora' object
# The vignette states "phytophthora data set (included in acde)"
# This means it's available via data() after loading the package.
data(phytophthora)

# Reproduce the 'desPI' object as shown in vignette chunks 4, 11, and 17
desPI <- vector("list",4)
for(tp in 1:4) desPI[[tp]] <- c(rep(1,8), rep(2,8))

# Serialize the objects to the required input files
saveRDS(phytophthora, "phytophthora.rds")
saveRDS(desPI, "desPI.rds")