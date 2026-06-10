# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clippda")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clippda)

# Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette loads these datasets directly using data()
data(liverRawData)
data(liver_pheno)

# Serialize the objects to the declared input files
# The workflow reads these as CSVs with stringsAsFactors = FALSE.
# write.csv by default writes character vectors as quoted strings,
# and factors as their levels (which are usually strings).
# Using row.names = FALSE ensures the CSVs do not contain an extra column
# for R's internal row names, which would be misinterpreted by the workflow's read.csv.
write.csv(liverRawData, "raw_mass_spec_peaks.csv", row.names = FALSE)
write.csv(liver_pheno, "phenotypic_data.csv", row.names = FALSE)