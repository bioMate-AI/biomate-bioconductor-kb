# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BioNet", "DLBCL")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BioNet)
library(DLBCL)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load the interactome network object as used in the vignette (e.g., Chunk 2, 8, 27)
data(interactome)

# Load the expression data object (ExpressionSet) as used in the vignette (e.g., Chunk 8)
data(exprLym)

# 2. Serialize objects to EACH declared input file in the EXACT format the workflow reads

# For 'ppi_network.sif':
# The 'interactome' object is a graphNEL object. The BioNet package provides
# 'saveNetwork' to write network objects to various formats, including SIF.
saveNetwork(interactome, file = "ppi_network.sif", type = "SIF")

# For 'expression_data.gct':
# The 'exprLym' object is an ExpressionSet. The BioNet package provides
# 'writeGct' to write ExpressionSet objects to the GCT format.
# We use the 'Gene.name' column from fData(exprLym) as the description column,
# as it provides more descriptive gene information than just the symbol.
writeGct(exprLym, file = "expression_data.gct", description.column = "Gene.name")