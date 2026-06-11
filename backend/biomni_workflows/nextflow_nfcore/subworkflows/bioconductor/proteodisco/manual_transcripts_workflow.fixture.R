library(ProteoDisco)
library(S4Vectors)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)
library(BSgenome.Hsapiens.UCSC.hg19)

# Load the manualSeq dataset shipped with ProteoDisco
data("manualSeq", package = "ProteoDisco")

# Serialize the object to the working directory as expected by the workflow
saveRDS(manualSeq, "manualSeq.rds")