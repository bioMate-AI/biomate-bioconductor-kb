library(aCGH)

# Load the dataset from the package
data(colorectal)

# Reproduce the vignette's data-preparation code to create colorectal.na
sex <- phenotype(colorectal)$sex
sex.na <- !is.na(sex)
index.clones.use <- which(clones.info(colorectal)$Chrom < 23)
colorectal.na <- colorectal[index.clones.use, sex.na, keep=TRUE]

# Serialize the object to the declared input file
saveRDS(colorectal.na, "colorectal.na")