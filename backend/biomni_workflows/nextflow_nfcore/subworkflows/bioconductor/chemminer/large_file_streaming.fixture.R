library(ChemmineR)

# Load the sample SDFset provided by the package
data(sdfsample)
sdfset <- sdfsample

# Export the SDFset to the required input file 'test.sdf'
write.SDF(sdfset, file="test.sdf", sig=TRUE)