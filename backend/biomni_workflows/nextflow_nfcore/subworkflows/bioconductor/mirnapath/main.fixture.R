library("miRNApath")

data(mirnaobj)

write.table(mirnaobj@mirnaTable, file="mirnaTable.txt", 
    quote=FALSE, row.names=FALSE, col.names=TRUE, na="",
    sep="\t")

write.table(mirnaobj@mirnaGene, file="mirnaGene.txt", 
    quote=FALSE, row.names=FALSE, col.names=TRUE, na="",
    sep="\t")

write.table(mirnaobj@mirnaPathways, file="mirnaPathways.txt", 
    quote=FALSE, row.names=FALSE, col.names=TRUE, na="",
    sep="\t")