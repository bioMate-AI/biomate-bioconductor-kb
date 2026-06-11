# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dks", "cubature")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dks)
library(cubature)

# Reproduce the vignette's data preparation code
# The vignette states: "To load the data set type data(dksdata)"
data(dksdata)

# The object P is now available in the environment, as confirmed by dim(P) in the vignette.

# Serialize the object P to each declared input file format

# P.csv: read by as.matrix(read.csv("P.csv", header = TRUE, check.names = FALSE))
# write.csv defaults to header=TRUE. row.names=FALSE prevents an extra column.
write.csv(P, "P.csv", row.names = FALSE)

# P.tsv: read by as.matrix(read.delim("P.tsv", header = TRUE, check.names = FALSE))
# read.delim implies tab-separated.
write.table(P, "P.csv", sep = "\t", row.names = FALSE, col.names = TRUE)

# P.rds: read by readRDS("P.rds")
saveRDS(P, "P.csv")

# P (plain text): read by as.matrix(read.table("P", header = TRUE, check.names = FALSE))
# read.table defaults to whitespace separation.
write.table(P, "P.csv", sep = " ", row.names = FALSE, col.names = TRUE)