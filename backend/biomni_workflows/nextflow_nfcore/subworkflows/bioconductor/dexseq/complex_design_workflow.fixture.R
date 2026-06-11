library(DEXSeq)
library(pasilla)

# Load the example data from the pasilla package as shown in the vignette
data(pasillaDEXSeqDataSet, package="pasilla")

# Ensure the object is named 'dxd' as expected by the workflow
if (!exists("dxd") && exists("pasillaDEXSeqDataSet")) {
    dxd <- pasillaDEXSeqDataSet
}

# Serialize the DEXSeqDataSet object to the expected input file
saveRDS(dxd, file="dxd")