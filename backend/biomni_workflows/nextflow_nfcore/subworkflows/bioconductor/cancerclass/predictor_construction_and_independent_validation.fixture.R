# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cancerclass", "cancerdata", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cancerclass) # As per prompt, load the main package
library(cancerdata) # For VEER and VIJVER datasets
library(Biobase)    # ExpressionSet class definition

# Load the datasets as shown in the vignette (Chunk 6)
data(VEER)
data(VIJVER)

# Create VIJVER2 as shown in the vignette (Chunk 6)
VIJVER2 <- VIJVER[, setdiff(sampleNames(VIJVER), sampleNames(VEER))]

# Serialize the objects to the declared input files
# The workflow reads using readRDS, so we use saveRDS.
# The input file names are 'training_file' and 'validation_file'.

# Save VEER as the training_file
training_file <- "training_file"
saveRDS(VEER, file = training_file)

# Save VIJVER2 as the validation_file
validation_file <- "validation_file"
saveRDS(VIJVER2, file = validation_file)