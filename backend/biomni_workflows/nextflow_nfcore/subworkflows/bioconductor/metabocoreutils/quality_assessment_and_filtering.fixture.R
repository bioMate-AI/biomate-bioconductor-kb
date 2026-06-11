# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MetaboCoreUtils")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MetaboCoreUtils)

# Read the feature values dataset as demonstrated in the vignette
vals_file <- system.file("txt", "feature_values.txt", package = "MetaboCoreUtils")
vals <- read.table(vals_file, sep = "\t")
vals <- as.matrix(vals)

# Identify biological study samples and QC (POOL) samples
study_cols <- grep("study", colnames(vals))
pool_cols <- grep("POOL", colnames(vals))

metabolomics_data <- vals[, study_cols, drop = FALSE]
qc_samples <- vals[, pool_cols, drop = FALSE]

# Create blank samples using a subset of the data to avoid random generation
blank_samples <- vals[, 1:2, drop = FALSE]
colnames(blank_samples) <- c("blank_01", "blank_02")
blank_samples[] <- NA # Blanks typically have missing or very low values

# Serialize the objects to the declared input files
write.table(metabolomics_data, file = "metabolomics_data", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
write.table(qc_samples, file = "qc_samples", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
write.table(blank_samples, file = "blank_samples", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)