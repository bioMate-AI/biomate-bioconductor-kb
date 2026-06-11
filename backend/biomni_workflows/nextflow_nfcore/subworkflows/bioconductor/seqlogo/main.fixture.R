# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("seqLogo")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(seqLogo)

# Recreate the position weight matrix (PWM) from the vignette
m <- data.frame(
  V1 = c(0.0, 0.8, 0.2, 0.0),
  V2 = c(0.0, 0.2, 0.8, 0.0),
  V3 = c(0.0, 0.8, 0.2, 0.0),
  V4 = c(0.3, 0.3, 0.4, 0.0),
  V5 = c(0.2, 0.4, 0.3, 0.1),
  V6 = c(0.0, 0.2, 0.8, 0.0),
  V7 = c(0.0, 0.8, 0.2, 0.0),
  V8 = c(0.0, 0.2, 0.8, 0.0)
)

# Write the matrix to the expected input file
write.table(m, "pwm_matrix.txt", row.names = FALSE, col.names = FALSE, sep = "\t")