# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("anota")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("anota")
data(anotaDataSet)

# The vignette uses subsetted dataT and dataP for the analysis,
# but the full anotaPhenoVec.
# We create these exact objects to be saved as inputs.
dataT_input <- anotaDataT[1:200,]
dataP_input <- anotaDataP[1:200,]
phenoVec_input <- anotaPhenoVec

# Save the objects to the specified input files using saveRDS,
# as indicated by the workflow's find_and_read_matrix/vector functions
# prioritizing readRDS.
saveRDS(dataT_input, "dataT")
saveRDS(dataP_input, "dataP")
saveRDS(phenoVec_input, "phenoVec")