library(Biostrings)
library(GenomAutomorphism)

# Load the dataset as demonstrated in the vignette
data(covid_aln, package = "GenomAutomorphism")

# Serialize the object to the expected input files
# Writing both the exact requested name and the .rds extension to satisfy the workflow's conditional logic
saveRDS(covid_aln, "covid_aln")
saveRDS(covid_aln, "covid_aln.rds")