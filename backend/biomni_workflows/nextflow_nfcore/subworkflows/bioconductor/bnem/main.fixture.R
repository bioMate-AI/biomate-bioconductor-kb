# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bnem")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bnem)

# Set seed for reproducibility as in the vignette
set.seed(9247)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The simBoolGtn function with keepsif = TRUE generates a SIF file
# named "PKN.sif" in the working directory.
sim <- simBoolGtn(Sgenes = 10, maxEdges = 10, keepsif = TRUE, negation = 0.1, layer = 1)

# The 'fc' object is directly available from the simulation result
fc_data <- addNoise(sim, sd = 1)

# 2. Serialize the objects to the declared input files

# For 'sifMatrix':
# The workflow expects a file named 'sifMatrix'.
# The simBoolGtn function creates 'PKN.sif'. We rename it.
file.rename("PKN.sif", "sifMatrix")

# For 'fc':
# The workflow reads 'fc' as a tab-separated file with header and row names.
write.table(fc_data, file = "fc", sep = "\t", col.names = TRUE, row.names = TRUE, quote = FALSE)