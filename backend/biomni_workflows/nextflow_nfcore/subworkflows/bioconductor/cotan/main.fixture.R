# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("COTAN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(COTAN)

# The vignette uses data(vignette.cells.origin) to load cell origin information.
# This object is a named factor vector.
data(vignette.cells.origin)

# The vignette downloads 'rawDataset' from GEO online.
# As per the critical instruction "MUST run fully OFFLINE",
# we use an example dataset shipped with the COTAN package itself.
# The 'cotan_small' object is a COTAN object containing raw counts.
data(cotan_small)

# Extract the raw counts matrix from the 'cotan_small' object.
# This matrix will serve as the content for the 'rawDataset' input file.
rawDataset_matrix <- getRaw(cotan_small)

# Serialize 'rawDataset_matrix' to a file named "rawDataset".
# The workflow reads this file using `read.csv(..., sep = "\t", row.names = 1L)`.
# Therefore, we write a tab-separated file with row names included as the first column.
write.table(rawDataset_matrix, file = "rawDataset", sep = "\t", quote = FALSE, col.names = NA)

# Serialize 'vignette.cells.origin' to a file named "vignette.cells.origin".
# Since 'vignette.cells.origin' is an R object (a named factor vector)
# and the workflow uses it directly after loading via `data()`,
# saving it as an RDS file ensures its exact structure is preserved for R.
saveRDS(vignette.cells.origin, file = "vignette.cells.origin")

# Clean up objects from the environment to ensure only the files are the output.
rm(rawDataset_matrix, cotan_small, vignette.cells.origin)