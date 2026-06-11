# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AMARETTO")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AMARETTO)

# 1. Prepare and serialize CancerSite
# As per the vignette, CancerSite is set to "LIHC".
CancerSite <- "LIHC"
writeLines(CancerSite, "CancerSite")

# 2. Prepare and serialize BatchData
# The vignette loads BatchData from "../inst/extdata/MethylStates.rda".
# We use system.file to access this file from the installed package.
batch_data_source_path <- system.file("extdata", "MethylStates.rda", package = "AMARETTO")

# Load the BatchData object into a temporary environment to avoid polluting the global environment.
# The vignette implies that 'BatchData' is an object made available by loading this .rda file.
env <- new.env()
load(batch_data_source_path, envir = env)

# Extract the BatchData object from the temporary environment.
# This assumes 'MethylStates.rda' contains an object named 'BatchData'.
BatchData <- env$BatchData

# Serialize the BatchData object to a file named "BatchData".
# The workflow uses load(batch_data_file), so saving as an RData file is appropriate.
save(BatchData, file = "BatchData")

# 3. Prepare and serialize gmt_file
# The vignette defines gmt_file using system.file to point to a GMT file within the package.
gmt_file_source_path <- system.file("templates/H.C2CP.genesets.gmt", package = "AMARETTO")

# Copy the GMT file to the current working directory with the expected input file name "gmt_file".
file.copy(gmt_file_source_path, "gmt_file", overwrite = TRUE)