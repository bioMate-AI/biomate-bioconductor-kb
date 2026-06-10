# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scRepertoire")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scRepertoire)

# Reproduce the VIGNETTE'S OWN data-preparation code
# Load the built-in example dataset
data("contig_list")

# Create the 'combined.TCR' object using combineTCR()
# This uses the 'contig_list' object loaded above
combined.TCR <- combineTCR(contig_list,
                           samples = c("P17B", "P17L", "P18B", "P18L", "P19B","P19L", "P20B", "P20L"),
                           removeNA = FALSE,
                           removeMulti = FALSE,
                           filterMulti = FALSE)

# Serialize the objects to the declared input files
# The workflow reads 'combined.TCR' and 'scRep_example' using readRDS.

# Save combined.TCR
saveRDS(combined.TCR, "combined.TCR")

# The vignette refers to 'contig_list' as the "built-in example data".
# We assume 'scRep_example' in the workflow refers to this initial example data object.
saveRDS(contig_list, "scRep_example")