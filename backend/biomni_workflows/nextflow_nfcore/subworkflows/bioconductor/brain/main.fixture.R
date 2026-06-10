# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BRAIN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BRAIN)

# Reproduce the vignette's own data-preparation code to materialize the example object.
# The vignette loads 'uniprotBRAIN.txt' which contains atomic compositions.
uniprotBRAIN <- read.table(system.file("extdata", "uniprotBRAIN.txt", package="BRAIN"))

# The workflow reads 'chemical_composition.txt'.
# Based on the vignette's use of atomic compositions (e.g., angiotensineII, humandynein,
# and the structure of uniprotBRAIN), it's inferred that 'chemical_composition.txt'
# should contain a table of atomic counts (C, H, N, O, S).
# We extract these columns from the 'uniprotBRAIN' dataset.
chemical_composition_data <- uniprotBRAIN[, c("C", "H", "N", "O", "S")]

# Serialize the extracted atomic composition data to 'chemical_composition.txt'.
# Using tab-separated format without row names or quotes, consistent with common
# Bioconductor text file formats and how 'uniprotBRAIN.txt' itself is read.
write.table(chemical_composition_data, "chemical_composition.txt", 
            sep="\t", row.names=FALSE, quote=FALSE)