# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GraphAlignment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GraphAlignment)

# Generate the example object as done in the vignette
ex <- GenerateExample(dimA=22, dimB=22, filling=.5, 
    covariance=.6, symmetric=TRUE, numOrths=10, correlated=seq(1,18))

# The workflow parser identified ex$a, ex$b, and ex$r as input files.
# Since the read excerpt is empty, we serialize them as RDS files 
# to preserve their matrix structure, using the exact requested filenames.
saveRDS(ex$a, "ex$a")
saveRDS(ex$b, "ex$b")
saveRDS(ex$r, "ex$r")

# Also write them as plain text tables in case the workflow uses read.table/read.csv
# but expects the literal filenames "ex$a", "ex$b", "ex$r"
write.table(ex$a, "ex$a", sep=",", row.names=FALSE, col.names=FALSE)
write.table(ex$b, "ex$b", sep=",", row.names=FALSE, col.names=FALSE)
write.table(ex$r, "ex$r", sep=",", row.names=FALSE, col.names=FALSE)