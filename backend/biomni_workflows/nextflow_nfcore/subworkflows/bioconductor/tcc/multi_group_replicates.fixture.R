# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TCC")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TCC)

# Reproduce data-preparation code from vignette chunk 16
data(hypoData_mg)
group <- c(1, 1, 1, 2, 2, 2, 3, 3, 3)

# Serialize hypoData_mg
saveRDS(hypoData_mg, "hypoData_mg.rds")
write.csv(hypoData_mg, "hypoData_mg.rds", row.names = TRUE, quote = FALSE)

# Serialize group
saveRDS(group, "group.rds")
write.table(group, "group.rds", col.names = FALSE, row.names = FALSE, quote = FALSE)