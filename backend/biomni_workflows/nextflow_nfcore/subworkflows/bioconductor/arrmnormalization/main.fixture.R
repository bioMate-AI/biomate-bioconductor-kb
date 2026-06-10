# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ARRmData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ARRmData)

# Load the datasets as per the vignette's data-preparation code
data(greenControlMatrix)
data(redControlMatrix)
data(betaMatrix)
data(sampleNames)

# Serialize betaMatrix
saveRDS(betaMatrix, "betaMatrix.rds")
write.csv(betaMatrix, "betaMatrix.rds", row.names = TRUE, quote = FALSE)

# Serialize greenControlMatrix
saveRDS(greenControlMatrix, "greenControlMatrix.rds")
write.csv(greenControlMatrix, "greenControlMatrix.rds", row.names = TRUE, quote = FALSE)

# Serialize redControlMatrix
saveRDS(redControlMatrix, "redControlMatrix.rds")
write.csv(redControlMatrix, "redControlMatrix.rds", row.names = TRUE, quote = FALSE)

# Serialize sampleNames
saveRDS(sampleNames, "sampleNames.rds")
writeLines(sampleNames, "sampleNames.rds")
write.csv(as.data.frame(sampleNames), "sampleNames.csv", row.names = FALSE, col.names = FALSE, quote = FALSE)