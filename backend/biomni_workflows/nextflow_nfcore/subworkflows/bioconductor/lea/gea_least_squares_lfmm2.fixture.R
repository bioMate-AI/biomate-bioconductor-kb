library(LEA)

# Load simulated data as shown in the vignette
data("offset_example")

# Extract genotype matrix and environmental variables
Y <- offset_example$geno
X <- offset_example$env

# Create a target loci vector as referenced in the workflow
target <- sample(1:ncol(Y), 10)

# Serialize to the expected input files
saveRDS(Y, "Y.rds")
saveRDS(X, "X.rds")
saveRDS(target, "target.rds")