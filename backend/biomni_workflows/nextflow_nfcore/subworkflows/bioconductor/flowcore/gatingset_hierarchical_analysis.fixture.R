# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(flowCore)

# Load example data from flowCore
data(GvHD)
ff <- GvHD[[1]]

# Write the raw flow cytometry data file
write.FCS(ff, "fcsfiles.FCS")

# Create a compensation matrix object for the fluorescent channels
comp_mat <- diag(4)
colnames(comp_mat) <- c("FL1-H", "FL2-H", "FL3-H", "FL4-H")
rownames(comp_mat) <- c("FL1-H", "FL2-H", "FL3-H", "FL4-H")
comp_obj <- compensation(comp_mat)

# Serialize the compensation matrix object
saveRDS(comp_obj, "comp")