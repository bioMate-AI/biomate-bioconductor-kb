# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ACE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ACE)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette uses the 'copyNumbersSegmented' dataset provided within the 'ace' package.
data("copyNumbersSegmented")

# The vignette assigns this dataset to an object named 'object' for subsequent analysis.
object <- copyNumbersSegmented

# 2. Serialize the object to the declared input file(s)
# The workflow reads a "Segmented template data frame".
# The vignette demonstrates saving the QDNAseq object itself as an RDS file
# when 'runACE' is called with 'filetype="rds"'.
# This RDS file containing the QDNAseq object serves as the segmented data input.
# The vignette's saveRDS call was incomplete; it should specify the object to save.
saveRDS(object, "copyNumbersSegmented.rds")

# CRITICAL NOTE: The prompt also declares "variant/mutation data frame" as an input file.
# However, the provided vignette excerpt does NOT contain any code for creating,
# loading, or using a "variant/mutation data frame".
# Per the instruction "reproduces the VIGNETTE'S OWN data-preparation code" and
# "NEVER invent a name, NEVER reference a package/object the documented code does not use",
# this script cannot generate a "variant/mutation data frame" as there is no
# corresponding data preparation code in the vignette to reproduce.
# Therefore, only the 'copyNumbersSegmented.rds' file is created based on the vignette's content.