# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("edge")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(edge)

# Reproduce data preparation from the vignette for the 'endotoxin' dataset
# This section corresponds to the 'endotoxin_import_data' chunk in the vignette.
data(endotoxin)
endoexpr <- endotoxin$endoexpr
class <- endotoxin$class
ind <- endotoxin$ind
time <- endotoxin$time

# Serialize the prepared objects to files in the working directory.
# The workflow's helper functions prioritize reading .rds files.
# For 'endoexpr' (matrix input):
saveRDS(endoexpr, "endoexpr.rds")

# For 'class' (vector input):
saveRDS(class, "class.rds")

# For 'time' (vector input, later converted to numeric by workflow):
saveRDS(time, "time.rds")

# For 'ind' (vector input):
saveRDS(ind, "ind.rds")