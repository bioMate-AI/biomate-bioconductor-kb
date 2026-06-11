# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ComPrAn", "data.table")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ComPrAn)
library(data.table)

# Locate the example peptide input file provided by the ComPrAn package
peptide_example_path <- system.file("extData", "data.txt", package = "ComPrAn")

# Read the example peptide data into an R object
# The vignette describes the input as a tab-delimited text file.
# data.table::fread is used for efficient reading of such files.
peptide_data <- data.table::fread(peptide_example_path)

# Serialize the peptide data to the required input file name 'peptide_input.txt'
# The vignette specifies tab-delimited values with column headers.
# data.table::fwrite is used to write the data in the specified format.
data.table::fwrite(peptide_data, file = "peptide_input.txt", sep = "\t")