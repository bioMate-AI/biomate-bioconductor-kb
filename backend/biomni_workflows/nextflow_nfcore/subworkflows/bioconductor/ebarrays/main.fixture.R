# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("EBarrays")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(EBarrays)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette loads the 'gould' dataset directly from the package.
data(gould)

# 2. Serialize that object to EACH declared input file in the EXACT format the workflow reads

# Save as gould.rds (for readRDS("gould.rds"))
saveRDS(gould, "gould.rds")

# Save as gould.csv (for as.matrix(read.csv("gould.csv", row.names = 1)))
write.csv(gould, "gould.rds", row.names = TRUE)

# Save as gould (for as.matrix(read.table("gould", header = TRUE, row.names = 1)))
# Use tab separator, no quotes, and include row/column names as per read.table arguments
write.table(gould, "gould.rds", sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)