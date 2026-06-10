# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DEsingle")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DEsingle)

# Load the test data as described in the vignette
data(TestData)

# The vignette re-defines 'group' in the usage example,
# matching the summary of the loaded 'group' object.
# We use this explicit definition to ensure reproducibility.
group <- factor(c(rep(1,50), rep(2,100)))

# Save the 'counts' matrix to 'counts.ext' using saveRDS,
# as the workflow's helper function prioritizes reading RDS files.
saveRDS(counts, "counts.ext")

# Save the 'group' factor vector to 'group.ext' using saveRDS,
# as the workflow's helper function prioritizes reading RDS files.
saveRDS(group, "group.ext")