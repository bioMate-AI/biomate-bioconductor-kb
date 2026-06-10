# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ClassifyR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ClassifyR)

# Reproduce the vignette's data preparation
data(asthma)

# Serialize 'measurements' object
saveRDS(measurements, "measurements.rds")
write.csv(measurements, "measurements.rds", row.names = TRUE, quote = FALSE)
write.table(measurements, "measurements.rds", sep = "\t", row.names = TRUE, quote = FALSE)

# Serialize 'classes' object
saveRDS(classes, "classes.rds")
# For CSV/TSV, the workflow expects a data frame with row names
# The 'classes' vector from data(asthma) does not have names,
# but it corresponds to the samples in 'measurements'.
# We create a data frame with sample names as row names and the class labels in a column.
classes_df <- data.frame(Class = classes, row.names = rownames(measurements))
write.csv(classes_df, "classes.rds", row.names = TRUE, quote = FALSE)
write.table(classes_df, "classes.rds", sep = "\t", row.names = TRUE, quote = FALSE)