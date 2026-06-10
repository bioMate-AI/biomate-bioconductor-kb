# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DELocal")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DELocal)

# 1. Reproduce the vignette's data-preparation code to materialize the example objects.

# For tooth_RNASeq_counts.txt:
# The vignette reads this file using `read.table` and then converts to matrix.
# Subsequent usage (e.g., `colnames(count_matrix)`, `rownames(count_matrix)`)
# implies the file has a header and the first column serves as row names.
# Inspection of the actual file from the package's extdata shows it is tab-separated.
counts_path_in_package <- system.file("extdata", "tooth_RNASeq_counts.txt", package = "DELocal")
count_matrix_data <- read.table(
    file = counts_path_in_package,
    header = TRUE,
    row.names = 1,
    sep = "\t"
)

# For Mouse_TAD_boundaries.csv:
# The vignette reads this file using `read.csv`.
# Subsequent usage (e.g., `gene_location_dynamicNeighbourhood$ensembl_gene_id`)
# implies the file has a header and the 'ensembl_gene_id' column is a regular column, not row names.
tad_path_in_package <- system.file("extdata", "Mouse_TAD_boundaries.csv", package = "DELocal")
tad_data <- read.csv(
    file = tad_path_in_package,
    header = TRUE # read.csv defaults to header=TRUE, but explicit is clearer
)

# 2. Serialize these objects to the declared input files in the exact format the workflow reads.

# Write tooth_RNASeq_counts.txt
# Use write.table with tab separator, including row and column names,
# to match the format expected by `read.table(..., header=TRUE, row.names=1, sep="\t")`.
write.table(
    x = count_matrix_data,
    file = "tooth_RNASeq_counts.txt",
    sep = "\t",
    quote = FALSE,
    row.names = TRUE,
    col.names = TRUE
)

# Write Mouse_TAD_boundaries.csv
# Use write.csv, ensuring no row names are written, to match the format
# expected by `read.csv(...)` where 'ensembl_gene_id' is a data column.
write.csv(
    x = tad_data,
    file = "Mouse_TAD_boundaries.csv",
    quote = FALSE,
    row.names = FALSE
)