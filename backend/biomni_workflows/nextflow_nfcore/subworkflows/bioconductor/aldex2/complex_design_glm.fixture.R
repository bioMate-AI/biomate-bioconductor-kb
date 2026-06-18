# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ALDEx2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ALDEx2)

# Reproduce the vignette's data preparation
data(selex)
selex.sub <- selex[1200:1600, ]
conds <- c(rep("NS", 7), rep("S", 7))

# Create the covariates data frame based on the vignette's conditions
covariates <- data.frame(
    condition = conds,
    row.names = colnames(selex.sub)
)

# Write CSV to match the workflow's FIRST reader, read.csv(row.names=1). A TSV here
# is silently mis-parsed by read.csv into a 1-column frame (the fallback read.table
# only fires if read.csv THROWS, which it does not), breaking model.matrix(~ .).
write.csv(selex.sub, file = "selex.sub")
write.csv(covariates, file = "covariates")