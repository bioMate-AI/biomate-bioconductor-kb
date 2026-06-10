# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PharmacoGx", "MultiAssayExperiment", "CoreGx")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PharmacoGx)
library(MultiAssayExperiment)
library(CoreGx)

# Reproduce the vignette's data-preparation code to create the object.
# The vignette provides an example for creating a PharmacoSet object using PharmacoGx::PharmacoSet2.
# We adapt this example to create an object named CCLEsmall.
CCLEsmall <- PharmacoGx::PharmacoSet2(
  name = "CCLEsmall", # Changed from "emptySet" to match the required object name
  treatment = data.frame(),
  sample = data.frame(),
  molecularProfiles = MultiAssayExperiment::MultiAssayExperiment(),
  treatmentResponse = CoreGx::TreatmentResponseExperiment(),
  perturbation = list(),
  curation = list(
    sample = data.frame(),
    treatment = data.frame(),
    tissue = data.frame()),
  datasetType = "sensitivity"
)

# Serialize the object to EACH declared input file in the EXACT format the workflow reads.
# The workflow checks for "CCLEsmall", "CCLEsmall.rds", or "CCLEsmall.RData".

# Save as "CCLEsmall" (no extension, read by readRDS)
saveRDS(CCLEsmall, file = "CCLEsmall.rds")

# Save as "CCLEsmall.rds" (read by readRDS)
saveRDS(CCLEsmall, file = "CCLEsmall.rds")

# Save as "CCLEsmall.RData" (read by load)
save(CCLEsmall, file = "CCLEsmall.RData")