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

# Load the interactome object from the BioNet vignette
data(interactome)

# Save the interactome object as ppi_network.sif
# The workflow reads this using loadNetwork.sif, so saveNetwork.sif is the appropriate counterpart.
saveNetwork.sif(interactome, "ppi_network.sif")

# Load the exprLym ExpressionSet object from the DLBCL package
data(exprLym)

# Extract the expression matrix from exprLym
expression_matrix <- exprs(exprLym)
num_rows <- nrow(expression_matrix)
num_cols <- ncol(expression_matrix)

# Get feature names (probe IDs) for the 'Name' column of the GCT file
gene_names <- featureNames(exprLym)

# Get gene descriptions from fData(exprLym) for the 'Description' column
# Handle cases where 'Gene.name' might be missing or contain NAs by replacing them with empty strings.
gene_descriptions <- fData(exprLym)$Gene.name
if (is.null(gene_descriptions) || length(gene_descriptions) == 0) {
    gene_descriptions <- rep("", num_rows)
}