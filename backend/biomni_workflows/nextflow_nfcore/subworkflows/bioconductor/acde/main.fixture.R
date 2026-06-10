# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("acde")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(acde)

# Reproduce the vignette's data preparation for 'dat' and 'des'
# From vignette chunk 2 and 6:
# dat is the third element of the phytophthora list, which is a matrix.
dat <- acde::phytophthora[[3]]
# des is a numeric vector representing the experimental design.
des <- c(rep(1,8), rep(2,8))

# Serialize 'dat' to 'dat.csv'
# The workflow reads: dat <- as.matrix(read.csv("dat.csv", row.names = 1, check.names = FALSE))
# This requires 'dat' to be saved as a CSV where the first column contains the row names.
write.csv(dat, "dat.csv", row.names = TRUE)

# Serialize 'des' to 'des.txt'
# The workflow reads: des <- scan("des.txt", what = numeric(), quiet = TRUE)
# This requires 'des' to be saved as a plain text file with numbers, typically one per line.
write(des, "des.txt")