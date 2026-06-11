library(planttfhunter)
library(Biostrings)

# Load the example AAStringSet object from the package
data(gsu, package = "planttfhunter")

# Write the protein sequences to the expected FASTA file
writeXStringSet(gsu, filepath = "proteome.fasta")