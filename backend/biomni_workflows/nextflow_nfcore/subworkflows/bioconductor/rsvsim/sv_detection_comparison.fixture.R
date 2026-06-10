library(RSVSim)
library(Biostrings)

# Create toy genome from vignette
genome = DNAStringSet(
  c("AAAAAAAAAAAAAAAAAAAATTTTTTTTTTTTTTTTTTTT", 
    "GGGGGGGGGGGGGGGGGGGGCCCCCCCCCCCCCCCCCCCC")
)
names(genome) = c("chr1","chr2")

# Simulate SVs
sim = simulateSV(output=NA, genome=genome, dels=5, sizeDels=5,
                 bpSeqSize=10, seed=2345, verbose=FALSE)
simSVs = metadata(sim)$deletions

# Write simulated SVs to CSV
write.csv(simSVs, "simulated_svs.csv", row.names=FALSE)

# Create query SVs
querySVs = data.frame(
  chr=c("chr1","chr1","chr1","chr2","chr2"),
  start=c(12,17,32,2,16), 
  end=c(15,24,36,6,20), 
  bpSeq=c("AAAAAAAAAA", "AAAAAAATTT", "TTTTTTTTTT", 
          "GGGGGGGGGG", "GGGGGGCCCC")
)

# Write query SVs to BED format
write.table(querySVs, "query_svs.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)