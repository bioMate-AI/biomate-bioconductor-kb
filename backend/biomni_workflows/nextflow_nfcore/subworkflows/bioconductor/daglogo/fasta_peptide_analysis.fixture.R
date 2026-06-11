# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dagLogo")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dagLogo)

# Get the path to the original grB.txt and HUMAN.fasta files from the dagLogo package
original_grB_path <- system.file("extdata", "grB.txt", package = "dagLogo")
original_HUMAN_fasta_path <- system.file("extdata", "HUMAN.fasta", package = "dagLogo")

# Read the content of grB.txt from the package's extdata
# The workflow reads it as: dat <- unlist(read.delim("grB.txt", header = FALSE, as.is = TRUE))
# This implies a single-column, tab-separated (default for read.delim) file without a header.
grB_content <- read.delim(original_grB_path, header = FALSE, as.is = TRUE)

# Write the content to a new grB.txt in the current working directory
# Ensure it matches the format expected by read.delim("grB.txt", header = FALSE, as.is = TRUE)
write.table(grB_content, file = "grB.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Copy the HUMAN.fasta file from the package's extdata to the current working directory
# This ensures the exact FASTA file used in the vignette is available.
file.copy(original_HUMAN_fasta_path, "HUMAN.fasta", overwrite = TRUE)