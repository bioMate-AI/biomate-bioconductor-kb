library(LEA)

# Load the tutorial dataset provided by the LEA package
data("tutorial")

# Write genotypes in the lfmm format to "genotypes.lfmm"
write.lfmm(tutorial.R, "genotypes.lfmm")

# Write the environment gradient file to "gradients.env"
write.env(tutorial.C, "gradients.env")