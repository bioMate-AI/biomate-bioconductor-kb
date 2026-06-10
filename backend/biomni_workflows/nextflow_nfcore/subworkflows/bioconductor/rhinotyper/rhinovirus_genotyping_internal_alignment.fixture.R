library(rhinotypeR)
library(Biostrings)

# Load example data from the package
data(rhinovirusVP4, package = "rhinotypeR")

# Remove gaps to create unaligned user sequences as expected by the workflow
aln_no_gaps <- Biostrings::DNAStringSet(
  gsub("-", "", as.character(rhinovirusVP4))
)

# Write to the expected input file
Biostrings::writeXStringSet(aln_no_gaps, filepath = "user_sequences.fasta")