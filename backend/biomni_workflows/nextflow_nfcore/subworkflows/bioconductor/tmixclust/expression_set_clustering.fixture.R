library(TMixClust)
library(SPEM)

# Load the SOS pathway data from Bioconductor package SPEM
data(sos)

# Save the ExpressionSet object to the expected input file
saveRDS(sos, "sos")