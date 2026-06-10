library(BSgenome)
library(BSgenome.Hsapiens.UCSC.hg38.masked)

genome <- BSgenome.Hsapiens.UCSC.hg38.masked
saveRDS(genome, file = "BSgenome.Hsapiens.UCSC.hg38.masked")