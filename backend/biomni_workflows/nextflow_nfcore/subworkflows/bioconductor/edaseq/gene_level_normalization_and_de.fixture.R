library(EDASeq)
library(yeastRNASeq)

# Load the datasets as demonstrated in the vignette
data(geneLevelData, package = "yeastRNASeq")
data(yeastGC, package = "EDASeq")
data(yeastLength, package = "EDASeq")

# Serialize the objects to the working directory
saveRDS(geneLevelData, "geneLevelData")
saveRDS(yeastGC, "yeastGC")
saveRDS(yeastLength, "yeastLength")