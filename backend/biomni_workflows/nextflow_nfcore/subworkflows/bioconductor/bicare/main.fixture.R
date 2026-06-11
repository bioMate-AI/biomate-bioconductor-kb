# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BicARE", "GSEABase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BicARE)
library(GSEABase) # Required for GeneSetCollection and GOCollection

# Reproduce the vignette's data-preparation code to materialize the example objects.

# 1. Create 'sample.bicData' (which will be saved as expression_set.RData)
data(sample.bicData)

# 2. Create 'gsc' (which will be saved as gene_sets.RData)
#    This requires the 'res.biclustering' object as an intermediate step.
set.seed(1)
res.biclustering <- FLOC(sample.bicData, k=15, pGene=0.3, pSample=0.6, r=0.01, 10, 8, 200)
gsc <- GeneSetCollection(res.biclustering$ExpressionSet[1:50], setType=GOCollection())

# Serialize the objects to the declared input files.
# The workflow uses `load()`, so we save the objects by their names.
save(sample.bicData, file = "expression_set.RData")
save(gsc, file = "gene_sets.RData")