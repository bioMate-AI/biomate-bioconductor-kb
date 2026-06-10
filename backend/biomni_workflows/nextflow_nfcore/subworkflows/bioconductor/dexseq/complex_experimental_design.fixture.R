library(DEXSeq)
library(pasilla)

# Load the example data from the pasilla package as shown in the vignette
data(pasillaDEXSeqDataSet, package="pasilla")

# Ensure the object is named 'dxd'
if (!exists("dxd") && exists("pasillaDEXSeqDataSet")) {
    dxd <- pasillaDEXSeqDataSet
}

# Serialize the DEXSeqDataSet object to the declared input file 'dxd'
saveRDS(dxd, file="dxd")