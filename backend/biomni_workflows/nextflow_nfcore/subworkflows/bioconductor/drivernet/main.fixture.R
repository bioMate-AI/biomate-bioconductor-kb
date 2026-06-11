# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DriverNet")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DriverNet)

# Reproduce the vignette's data-preparation code
data(samplePatientMutationMatrix)
data(samplePatientOutlierMatrix)
data(sampleInfluenceGraph)
data(sampleGeneNames)

# Serialize objects to the declared input files in the specified formats

# For matrices and graph objects, save as RDS as read_input tries readRDS first
saveRDS(samplePatientMutationMatrix, "samplePatientMutationMatrix.ext")
saveRDS(samplePatientOutlierMatrix, "samplePatientOutlierMatrix.ext")
saveRDS(sampleInfluenceGraph, "sampleInfluenceGraph.ext")

# For gene names, save as a plain text file with one gene per line,
# as read_input has a special case for it using readLines
writeLines(sampleGeneNames, "sampleGeneNames.ext")