library(crisprScore)

spacers <- c("ATCGATGCTGATGCTAGATA", "GAGTCCGAGCAGAAGAAGAA")
protospacers <- c("ATCGATGCTGATGCTAGATT", "GAGTCCGAGCAGAAGAAGAG")
pams <- c("AGG", "TGG")

writeLines(spacers, "spacers.txt")
writeLines(protospacers, "protospacers.txt")
writeLines(pams, "pams.txt")