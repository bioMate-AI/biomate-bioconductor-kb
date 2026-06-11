library(RSVSim)
library(Biostrings)

genome = DNAStringSet(
c("AAAAAAAAAAAAAAAAAAAATTTTTTTTTTTTTTTTTTTT", 
"GGGGGGGGGGGGGGGGGGGGCCCCCCCCCCCCCCCCCCCC"))
names(genome) = c("chr1","chr2")

sim = simulateSV(output=NA, genome=genome, dels=5, sizeDels=5,
bpSeqSize=10, seed=2345, verbose=FALSE)
simSVs = metadata(sim)$deletions

write.csv(simSVs, "simulated_svs.csv", row.names = FALSE, quote = FALSE)

querySVs = data.frame(
  chr=c("chr1","chr1","chr1","chr2","chr2"),
  start=c(12,17,32,2,16), 
  end=c(15,24,36,6,20), 
  bpSeq=c("AAAAAAAAAA", "AAAAAAATTT", "TTTTTTTTTT", 
    "GGGGGGGGGG", "GGGGGGCCCC")
)

write.table(querySVs, "detected_svs.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)