# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("destiny")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(destiny)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette explicitly uses `data(guo)` to load the sample data.
data(guo)

# 2. Serialize that object to EACH declared input file
# The workflow reads 'guo.rds' (an R object) or 'guo.csv' (a data frame)
# or 'guo' (a data frame, no extension).

# Save as guo.rds
saveRDS(guo, "guo.rds")

# Convert the matrix 'guo' to a data frame for CSV output
guo_df <- as.data.frame(guo)

# Save as guo.csv
# Use row.names = FALSE to match the typical behavior of read.csv when check.names = FALSE
write.csv(guo_df, "guo.rds", row.names = FALSE)

# Save as guo (no extension)
write.csv(guo_df, "guo.rds", row.names = FALSE)