# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TCC")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TCC)

# Load the 'hypoData' dataset as shown in multiple vignette chunks (e.g., chunk 1, 2, 4, etc.)
data(hypoData)

# Create the 'cl' object as a data frame, based on vignette chunk 12
# The 'group' vector is defined in many chunks (e.g., chunk 1, 2, 4, etc.)
group <- factor(c(1, 1, 1, 2, 2, 2))
cl <- data.frame(group = group)

# 2. Serialize objects to EACH declared input file in the EXACT format the workflow reads

# --- For 'hypoData' ---
# Save as RDS
saveRDS(hypoData, "hypoData.rds")

# Save as CSV (workflow reads with row.names = 1, check.names = FALSE)
# write.csv by default includes row names as the first column, matching row.names = 1.
# quote = FALSE is used to prevent unnecessary quoting of numeric data.
write.csv(hypoData, "hypoData.rds", row.names = TRUE, quote = FALSE)

# Save as TSV (workflow reads with row.names = 1, check.names = FALSE)
# write.table with sep = "\t" creates a TSV.
# row.names = TRUE includes row names as the first column.
# quote = FALSE is used to prevent unnecessary quoting of numeric data.
write.table(hypoData, "hypoData.rds", sep = "\t", row.names = TRUE, quote = FALSE)

# --- For 'cl' ---
# Save as RDS
saveRDS(cl, "cl.rds")

# Save as CSV (workflow reads with header = TRUE, check.names = FALSE)
# row.names = FALSE ensures that the first column is not interpreted as row names
# but rather the actual data, with the first row being the header.
# quote = FALSE is used for cleaner output.
write.csv(cl, "cl.rds", row.names = FALSE, quote = FALSE)

# Save as TSV (workflow reads with header = TRUE, check.names = FALSE)
# row.names = FALSE ensures no extra column for row names.
# quote = FALSE is used for cleaner output.
write.table(cl, "cl.rds", sep = "\t", row.names = FALSE, quote = FALSE)