# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("coseq", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(coseq)
library(Biobase)

data("fietz")
counts <- exprs(fietz)

write.table(counts, file = "counts.csv", sep = "\t", quote = FALSE, col.names = TRUE, row.names = TRUE)
write.csv(counts, file = "counts.csv", quote = FALSE, row.names = TRUE)
write.table(counts, file = "counts.csv", sep = "\t", quote = FALSE, col.names = TRUE, row.names = TRUE)