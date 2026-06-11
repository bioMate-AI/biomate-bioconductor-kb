library(mBPCR)
library(oligoClasses)

# Load the example dataset from oligoClasses as done in the vignette
data(oligoSetExample, package="oligoClasses")

# Serialize the oligoSet object to the declared input file
saveRDS(oligoSet, "oligoSet")