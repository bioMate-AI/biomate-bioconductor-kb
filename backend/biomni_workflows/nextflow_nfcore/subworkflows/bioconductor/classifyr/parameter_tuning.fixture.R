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

# Reproduce the VIGNETTE'S OWN data-preparation code
# This loads 'measurements' (a numeric matrix) and 'classes' (a factor vector)
data(asthma)

# Serialize 'measurements' to EACH declared input file

# measurements.rds
saveRDS(measurements, "measurements.rds")

# measurements.csv
# Workflow reads: as.matrix(read.csv("measurements.csv", row.names = 1, check.names = FALSE))
# Write with row names as the first column, no quotes for numeric data.
write.csv(measurements, "measurements.rds", row.names = TRUE, quote = FALSE)

# measurements.txt
# Workflow reads: as.matrix(read.table("measurements.txt", header = TRUE, row.names = 1, check.names = FALSE))
# Write as tab-separated, with header, row names as the first column, and an empty top-left cell.
write.table(measurements, "measurements.rds", sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)

# Serialize 'classes' to EACH declared input file

# classes.rds
saveRDS(classes, "classes.rds")

# classes.csv
# Workflow reads: classes_df <- read.csv("classes.csv", header = TRUE)
# Convert factor vector to a data frame with a column name, no row names, no quotes.
write.csv(data.frame(Class = classes), "classes.csv", row.names = FALSE, quote = FALSE)

# classes.txt
# Workflow reads: classes_df <- read.table("classes.txt", header = TRUE)
# Convert factor vector to a data frame with a column name, tab-separated, no row names, no quotes.
write.table(data.frame(Class = classes), "classes.txt", sep = "\t", row.names = FALSE, quote = FALSE)