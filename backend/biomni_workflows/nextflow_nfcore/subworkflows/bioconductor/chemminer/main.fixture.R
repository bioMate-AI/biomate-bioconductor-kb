library("ChemmineR")

# Load the sample dataset provided by the package
data(sdfsample)

# Write the SDFset object to the expected input file
write.SDF(sdfsample, file="sdfsample.sdf", sig=TRUE)