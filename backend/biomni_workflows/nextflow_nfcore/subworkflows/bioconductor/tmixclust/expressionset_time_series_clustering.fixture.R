library(TMixClust)
library(SPEM)

# Load the SOS pathway data from Bioconductor package SPEM
data(sos, package = "SPEM")

# Serialize the Biobase ExpressionSet object to the declared input file
saveRDS(sos, "sos")