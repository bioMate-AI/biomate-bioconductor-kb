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
data(asthma) # Contains measurements and classes variables.

# Create measurementsDF as shown in the vignette
measurementsDF <- DataFrame(measurements)
mcols(measurementsDF) <- data.frame(
  assay = rep(c("assay_1", "assay_2"), times = c(10, 1990)),
  feature = colnames(measurementsDF)
)

# Serialize the objects to the declared input files
saveRDS(measurementsDF, "measurementsDF.rds")
saveRDS(classes, "classes.rds")