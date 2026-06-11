library(puma)
library(pumadata)
library(oligo)

# Load the example FeatureSet from pumadata
data(oligo.estrogen)

# The oligo.estrogen object has 8 samples. 
# We create 8 dummy CEL files to match the dimensions.
celFiles <- paste0("sample", 1:8, ".CEL")

for (f in celFiles) {
    writeLines("Dummy CEL file content for testing.", f)
}

# Since we cannot write valid binary Affymetrix CEL files natively in R,
# and the workflow uses read.celfiles() without a namespace prefix,
# we mock read.celfiles in the global environment to return the valid FeatureSet.
read.celfiles <- function(filenames, ...) {
    return(oligo.estrogen)
}