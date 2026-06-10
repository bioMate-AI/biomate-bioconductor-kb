library("pRoloc")
library("pRolocdata")
library("MSnbase")

# Load the example dataset from the companion data package as shown in the vignette
data("andy2011")

# Extract the quantitation data, feature metadata, and sample metadata
# and serialize them to the exact CSV files expected by the workflow's readMSnSet call
write.csv(exprs(andy2011), file = "exprsFile.csv", row.names = TRUE)
write.csv(fData(andy2011), file = "fdataFile.csv", row.names = TRUE)
write.csv(pData(andy2011), file = "pdataFile.csv", row.names = TRUE)