library("ChemmineR")
data(sdfsample)
write.SDF(sdfsample, file="test.sdf", sig=TRUE)