# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bacon")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bacon)

# Reproduce the VIGNETTE'S OWN data-preparation code
# A vector containing 5000 z-scores is generated from a normal mixture distribution.
y <- rnormmix(5000, c(0.9, 0.2, 1.3, 1, 4, 1))

# Serialize the 'y' object to each declared input file in the exact format the workflow reads.

# Format 1: "y" (scanned as a vector)
# write() writes elements on separate lines by default, which scan() can read.
write(y, file = "y")

# Format 2: "y.csv" (read as a CSV, first column)
# write.csv() expects a data frame or matrix.
# We need to ensure it's written as a single column without header or row names.
write.csv(data.frame(y), file = "y.csv", row.names = FALSE, col.names = FALSE)

# Format 3: "y.txt" (scanned as a vector)
# write() writes elements on separate lines by default, which scan() can read.
write(y, file = "y.txt")