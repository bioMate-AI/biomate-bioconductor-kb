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

# Reproduce the vignette's data-preparation code
data(asthma) # This loads 'measurements' (numeric matrix) and 'classes' (factor vector)

# Serialize 'measurements' to measurements.rds
saveRDS(measurements, "measurements.rds")

# Serialize 'measurements' to measurements.csv
# The workflow reads with row.names = 1, so we must write row names.
# The workflow reads with check.names = FALSE, which is the default behavior for write.csv.
write.csv(measurements, "measurements.rds", row.names = TRUE)

# Serialize 'classes' to classes.rds
saveRDS(classes, "classes.rds")

# Serialize 'classes' to classes.csv
# The workflow reads into 'classes_df' with header = TRUE.
# We need to convert the 'classes' factor into a data frame with a header.
# A common practice is to name the column after the variable itself.
classes_df <- data.frame(classes = classes)
# The workflow's read.csv for classes.csv does not specify row.names,
# so we should write without row names to avoid an extra column of indices.
write.csv(classes_df, "classes.rds", row.names = FALSE)