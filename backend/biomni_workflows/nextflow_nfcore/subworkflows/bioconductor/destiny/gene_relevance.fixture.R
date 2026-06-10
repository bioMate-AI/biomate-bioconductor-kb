suppressPackageStartupMessages({
    library(destiny)
    library(Biobase)
    library(SingleCellExperiment)
})

# Load the example dataset from the destiny package
data(guo)

# Convert the ExpressionSet to a SingleCellExperiment object
# to match the expected input type (SingleCellExperiment)
sce <- SingleCellExperiment(
    assays = list(logcounts = exprs(guo)),
    colData = pData(guo)
)

# Save as the expected input file
saveRDS(sce, "allen_hvg")