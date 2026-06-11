# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("data.table", "PharmacoGx")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(data.table)
library(PharmacoGx)

# Reproduce the 'sample' data frame from the vignette
# This data frame will be saved as 'mathews_griner.csv' inside the tar.gz archive.
mathews_griner_content <- data.frame(
  sampleid = c("A549", "MCF7", "PC3"),
  tissueid = c("lung", "breast", "prostate"),
  cellosaurus.accession = c("CVCL_0023", "CVCL_0031", "CVCL_0035"),
  row.names = c("A549", "MCF7", "PC3")
)

# Define the names for the intermediate CSV file and the final tar.gz archive
output_csv_filename <- "mathews_griner.csv"
output_tar_gz_filename <- "mathews_griner.csv.tar.gz"

# Write the data frame to a CSV file
# Use fwrite from data.table for efficiency and compatibility with fread.
# Do not write row names as they are duplicated in the 'sampleid' column.
fwrite(mathews_griner_content, file = output_csv_filename, row.names = FALSE)

# Create a tar.gz archive containing the CSV file
# The utils::tar function can create compressed archives directly.
utils::tar(tarfile = output_tar_gz_filename, files = output_csv_filename, compression = "gzip")

# Clean up the intermediate CSV file
file.remove(output_csv_filename)