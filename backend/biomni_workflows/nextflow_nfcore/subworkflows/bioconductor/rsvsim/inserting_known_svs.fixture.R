library(RSVSim)
library(Biostrings)

genome = DNAStringSet(
c("AAAAAAAAAAAAAAAAAAAATTTTTTTTTTTTTTTTTTTT", 
"GGGGGGGGGGGGGGGGGGGGCCCCCCCCCCCCCCCCCCCC"))
names(genome) = c("chr1","chr2")

writeXStringSet(genome, "genome.fasta")