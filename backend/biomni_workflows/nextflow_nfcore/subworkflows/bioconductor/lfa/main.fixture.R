library(lfa)
library(genio)

# Load the example dataset from the lfa package
data("hgdp_subset", package = "lfa")

# The workflow expects PLINK format files: genotypes.bed, genotypes.bim, genotypes.fam
# We use genio::write_plink to serialize the hgdp_subset genotype matrix into these files
genio::write_plink("genotypes", X = hgdp_subset)

# Verify the required files were created successfully
stopifnot(
  file.exists("genotypes.bed"),
  file.exists("genotypes.bim"),
  file.exists("genotypes.fam")
)