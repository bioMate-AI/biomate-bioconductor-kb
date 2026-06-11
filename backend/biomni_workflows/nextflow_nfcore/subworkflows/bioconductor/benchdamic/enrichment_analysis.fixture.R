# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("benchdamic", "phyloseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(benchdamic)
library(phyloseq)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette states: "For Concordance and Enrichment analyses the ps_plaque_16S dataset is used"
# And provides the exact code:
data("ps_plaque_16S")

# 2. Serialize that object to EACH declared input file
# The workflow reads 'ps_plaque_16S' and 'microbial_metabolism'.

# For 'ps_plaque_16S':
# The object created by data("ps_plaque_16S") is a phyloseq-class object.
# The standard way to serialize such an R object is saveRDS().
saveRDS(ps_plaque_16S, file = "ps_plaque_16S.rds")

# For 'microbial_metabolism':
# The provided vignette does NOT contain any code to generate an R object
# named 'microbial_metabolism' or any data that could be serialized into a file
# of this name. To comply with the requirement to create "EACH declared input file"
# without inventing data or objects not present in the vignette, an empty file
# is created as a placeholder.
file.create("microbial_metabolism")