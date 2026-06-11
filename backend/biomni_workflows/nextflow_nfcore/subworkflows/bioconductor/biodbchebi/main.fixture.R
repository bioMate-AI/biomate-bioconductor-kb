# Load the required package
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("biodbChebi")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(biodbChebi)

# Create a synthetic dataset of ChEBI IDs
chebi_data <- data.frame(
  ChEBI_ID = c("CHEBI:15377", "CHEBI:15422", "CHEBI:16761", "CHEBI:17234"),
  Name = c("water", "ATP", "ADP", "glucose"),
  stringsAsFactors = FALSE
)

# Write the dataset to the expected input file
write.csv(chebi_data, file = "input.csv", row.names = FALSE)