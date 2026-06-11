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

# The vignette does not provide specific data-preparation code for 'GDSCsmall' or 'CCLEsmall'
# datasets. It only provides an example of how to construct an empty PharmacoSet object
# using the PharmacoGx::PharmacoSet2 constructor.
# To adhere strictly to the instruction "Reproduces the VIGNETTE'S OWN data-preparation code",
# we will create an empty PharmacoSet object as shown in the vignette's section 3.1
# "PharmacoGx 2.0" and save it as the required input files.

# Reproduce the PharmacoSet2 constructor call from the vignette
pSet_empty <- PharmacoGx::PharmacoSet2(
  name = "emptySet",
  treatment = data.frame(),
  sample = data.frame(),
  molecularProfiles = MultiAssayExperiment::MultiAssayExperiment(),
  treatmentResponse = CoreGx::TreatmentResponseExperiment(),
  perturbation = list(),
  curation = list(
    sample = data.frame(),
    treatment = data.frame(),
    tissue = data.frame()
  ),
  datasetType = "sensitivity"
)

# Serialize the created object to the specified input files
# The workflow reads these files using readRDS(), so saveRDS() is the correct format.
saveRDS(pSet_empty, file = "GDSCsmall.rds")
saveRDS(pSet_empty, file = "CCLEsmall.rds")