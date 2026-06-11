# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dearseq", "writexl", "utils", "stats")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dearseq)
library(writexl) # For writing .xlsx files
library(utils)   # For write.csv (base R)
library(stats)   # For relevel (base R)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load data objects directly from the dearseq package.
# These objects are pre-packaged versions of the data that would otherwise be
# fetched online via GEOquery, ensuring the script runs fully offline.
data("London", package = "dearseq")
data("infos_df", package = "dearseq")
# The 'genes' vector is also available in the package, corresponding to rownames(London).
data("genes", package = "dearseq") 

# Recreate the col_data data frame as shown in the vignette (Section 2.2.2)
col_data <- data.frame(Status = infos_df$Status)
col_data$Status <- stats::relevel(col_data$Status, ref = "Control")
rownames(col_data) <- infos_df$SampleTitle

# 2. Serialize objects to declared input files

# For expression_matrix.xlsx:
# The 'London' object is a numeric matrix. The original Excel file read in the
# vignette had a 'Genes' column followed by sample expression values.
# We reconstruct this format for the output file.
expression_matrix_df <- data.frame(Genes = rownames(London), London)
writexl::write_xlsx(expression_matrix_df, "expression_matrix.xlsx")

# For metadata.csv:
# The 'col_data' object is a data frame with 'SampleTitle' as row names and 'Status' as a column.
# We write it to CSV with 'SampleTitle' as the first column.
metadata_df <- data.frame(SampleTitle = rownames(col_data), col_data)
write.csv(metadata_df, "metadata.csv", row.names = FALSE)