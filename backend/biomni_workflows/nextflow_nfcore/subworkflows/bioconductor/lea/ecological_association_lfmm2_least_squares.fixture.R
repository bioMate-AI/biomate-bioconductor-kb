library(LEA)

# Create the tutorial files as shown in the vignette
data("tutorial")
write.lfmm(tutorial.R, "genotypes.lfmm")
write.geno(tutorial.R, "genotypes.geno")
write.env(tutorial.C, "gradients.env")

# Create the Y and X objects from the offset_example dataset
data("offset_example")
Y <- offset_example$geno
X <- offset_example$env

# Serialize Y and X to the working directory as requested
saveRDS(Y, "Y")
saveRDS(X, "X")

# Also write them in LEA's native formats just in case the workflow expects text matrices
write.lfmm(Y, "Y.lfmm")
write.env(X, "X.env")