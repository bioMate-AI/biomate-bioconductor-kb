library(msa)
library(Biostrings)

mySequenceFile <- system.file("examples", "exampleAA.fasta", package="msa")
mySequences <- readAAStringSet(mySequenceFile)
myFirstAlignment <- msa(mySequences)

saveRDS(myFirstAlignment, "myFirstAlignment")