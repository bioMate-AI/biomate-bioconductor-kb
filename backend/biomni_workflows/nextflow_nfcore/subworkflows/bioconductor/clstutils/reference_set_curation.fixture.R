library(ape)
library(lattice)
library(clst)
library(clstutils)

data(seqs, package="clstutils")
data(seqdat, package="clstutils")

saveRDS(seqs, "seqs.rds")
saveRDS(seqdat, "seqdat.rds")