# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("EpiMix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(EpiMix)

# Load the built-in datasets from the EpiMix package as demonstrated in the vignette
data(MET.data)
data(mRNA.data)
data(LUAD.sample.annotation)

# Write the datasets to the expected input files
write.csv(MET.data, file = "methylation_matrix.csv", row.names = TRUE)
write.csv(mRNA.data, file = "expression_matrix.csv", row.names = TRUE)
write.csv(LUAD.sample.annotation, file = "sample_metadata.csv", row.names = FALSE)