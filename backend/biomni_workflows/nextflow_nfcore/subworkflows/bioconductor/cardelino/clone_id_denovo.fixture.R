# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cardelino", "Matrix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cardelino)
library(Matrix)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette's data preparation for these specific files is to load them from system.file
AD_file_source <- system.file("extdata", "passed_ad.mtx", package = "cardelino")
DP_file_source <- system.file("extdata", "passed_dp.mtx", package = "cardelino")
id_file_source <- system.file("extdata", "passed_variant_names.txt", package = "cardelino")

AD <- Matrix::readMM(AD_file_source)
DP <- Matrix::readMM(DP_file_source)
var_ids <- read.table(id_file_source, )

# 2. Serialize the objects to EACH declared input file in the EXACT format the workflow reads
# For AD and DP, the workflow uses Matrix::readMM, so we use Matrix::writeMM
Matrix::writeMM(AD, file = "passed_ad.mtx")
Matrix::writeMM(DP, file = "passed_dp.mtx")

# For var_ids, the workflow uses read.table, so we use write.table
# Ensure no row names, column names, or quotes are written to match simple read.table behavior
write.table(var_ids, file = "passed_variant_names.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)