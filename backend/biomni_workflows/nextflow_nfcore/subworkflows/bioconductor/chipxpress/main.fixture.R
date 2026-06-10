# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ChIPXpress", "ChIPXpressData", "bigmemory")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ChIPXpress)
library(ChIPXpressData)
library(bigmemory)

# 1. Reproduce Oct4ESC_ChIPgenes object
data(Oct4ESC_ChIPgenes)

# 2. Serialize Oct4ESC_ChIPgenes to "Oct4ESC_ChIPgenes.csv"
# The workflow reads .csv first, and the vignette loads it as a data frame.
# Use row.names = FALSE to prevent an extra column for row names in the CSV.
write.csv(Oct4ESC_ChIPgenes, "Oct4ESC_ChIPgenes.csv", row.names = FALSE)

# 3. Reproduce DB_GPL1261.bigmemory.desc and its associated .bin file
# The vignette uses attach.big.matrix to load these files from the ChIPXpressData package.
# To create the fixture, we need to copy these files to the current working directory.
source_path <- system.file("extdata", package="ChIPXpressData")
file.copy(
  from = file.path(source_path, "DB_GPL1261.bigmemory.desc"),
  to = "DB_GPL1261.bigmemory.desc",
  overwrite = TRUE
)
file.copy(
  from = file.path(source_path, "DB_GPL1261.bigmemory.bin"),
  to = "DB_GPL1261.bigmemory.bin",
  overwrite = TRUE
)

# The DB_GPL1261 object itself is a big.matrix attached from these files.
# The workflow expects the .desc file (and its .bin counterpart) to exist.
# We don't need to attach it here, just ensure the files are present.
# If we were to attach it to verify, it would be:
# DB_GPL1261 <- attach.big.matrix("DB_GPL1261.bigmemory.desc", path=".")