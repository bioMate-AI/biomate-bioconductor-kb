library(LEA)

# Load the tutorial data provided by the package
data("tutorial", package = "LEA")

# Write genotypes in the lfmm format
write.lfmm(tutorial.R, "genotypes.lfmm")

# Write genotypes in the geno format (used in snmf steps)
write.geno(tutorial.R, "genotypes.geno")

# Write the environment gradient file
write.env(tutorial.C, "gradients.env")