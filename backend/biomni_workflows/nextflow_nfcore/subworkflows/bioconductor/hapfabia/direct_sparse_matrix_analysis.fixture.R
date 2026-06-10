library(hapFabia)

data(simu)
namesL <- simu[["namesL"]]
haploN <- simu[["haploN"]]
snvs <- simu[["snvs"]]
annot <- simu[["annot"]]
alleleIimp <- simu[["alleleIimp"]]

write.table(namesL, file="dataSim1fabia_individuals.txt",
    quote = FALSE, row.names = FALSE, col.names = FALSE)

write(as.integer(haploN), file="dataSim1fabia_annot.txt",
    ncolumns=100)
write(as.integer(snvs), file="dataSim1fabia_annot.txt",
    append=TRUE, ncolumns=100)
write.table(annot, file="dataSim1fabia_annot.txt", sep = " ",
    quote = FALSE, row.names = FALSE, col.names = FALSE, append=TRUE)

write(as.integer(haploN), file="dataSim1fabia_mat.txt", ncolumns=100)
write(as.integer(snvs), file="dataSim1fabia_mat.txt",
    append=TRUE, ncolumns=100)

for (i in 1:haploN) {
  a1 <- which(alleleIimp[i,] > 0.01)
  al <- length(a1)
  b1 <- alleleIimp[i, a1]

  a1 <- a1 - 1
  dim(a1) <- c(1, al)
  b1 <- format(as.double(b1), nsmall=1)
  dim(b1) <- c(1, al)

  write.table(al, file="dataSim1fabia_mat.txt", sep = " ",
     quote = FALSE, row.names = FALSE, col.names = FALSE, append=TRUE)
  write.table(a1, file="dataSim1fabia_mat.txt", sep = " ",
     quote = FALSE, row.names = FALSE, col.names = FALSE, append=TRUE)
  write.table(b1, file="dataSim1fabia_mat.txt", sep = " ",
     quote = FALSE, row.names = FALSE, col.names = FALSE, append=TRUE)
}