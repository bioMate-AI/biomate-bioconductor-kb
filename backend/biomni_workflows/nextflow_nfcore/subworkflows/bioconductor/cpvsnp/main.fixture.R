# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cpvSNP", "GSEABase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cpvSNP)
library(GSEABase) # Required for toGmt function

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data(geneSetAnalysis)

# Extract the necessary objects from the geneSetAnalysis list
arrayData_df <- geneSetAnalysis[["arrayData"]]
geneSets_gsc <- geneSetAnalysis[["geneSets"]]
indep_df <- geneSetAnalysis[["indepSNPs"]]

# 2. Serialize objects to EACH declared input file in the EXACT format the workflow reads

# Save arrayData_df to arrayData.csv
# The workflow reads with read.csv, so write.csv is appropriate.
# row.names = FALSE ensures the first column isn't treated as row names upon reading.
write.csv(arrayData_df, "arrayData.csv", row.names = FALSE)

# Save geneSets_gsc (GeneSetCollection) to gene_sets.gmt
# The toGmt function from GSEABase package is used for this format.
toGmt(geneSets_gsc, "gene_sets.gmt")

# Save indep_df to independent_snps.txt
# The workflow reads with read.table(..., header = FALSE),
# so write.table with col.names = FALSE and row.names = FALSE is appropriate.
# Using sep = "\t" for a common plain text format.
write.table(indep_df, "independent_snps.txt", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)