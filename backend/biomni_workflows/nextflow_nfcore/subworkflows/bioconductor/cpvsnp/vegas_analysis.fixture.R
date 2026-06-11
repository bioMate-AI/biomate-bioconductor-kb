# Load necessary packages
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cpvSNP", "GSEABase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cpvSNP)
library(GSEABase) # Required for the toGmt function to write GeneSetCollection objects

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the example dataset 'geneSetAnalysis' from the cpvSNP package.
# This dataset contains the raw data needed for arrayData.csv, gene_sets.gmt, and ld_matrix.rds.
data(geneSetAnalysis, package = "cpvSNP")

# 2. Serialize objects to declared input files in the exact format the workflow reads

# --- Generate arrayData.csv ---
# The workflow reads "arrayData.csv" into a data frame.
# The vignette uses geneSetAnalysis[["arrayData"]] (which is a data.frame)
# as the source for array data.
arrayData_df_to_write <- geneSetAnalysis[["arrayData"]]
write.csv(arrayData_df_to_write, "arrayData.csv", row.names = FALSE)

# --- Generate gene_sets.gmt ---
# The vignette uses geneSetAnalysis[["geneSets"]], which is a GeneSetCollection object.
# This object needs to be written to a .gmt file.
geneSets_to_write <- geneSetAnalysis[["geneSets"]]
# The GSEABase package provides the toGmt function for this purpose.
GSEABase::toGmt(geneSets_to_write, "gene_sets.gmt")

# --- Generate ld_matrix.rds ---
# The workflow reads "ld_matrix.rds" using readRDS.
# The vignette references geneSetAnalysis[["ldMat"]] as the linkage disequilibrium matrix.
ldMat_to_write <- geneSetAnalysis[["ldMat"]]
saveRDS(ldMat_to_write, "ld_matrix.rds")