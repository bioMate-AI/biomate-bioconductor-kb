library(PhyloProfile)

data("mainLongRaw", package = "PhyloProfile")

write.table(
    mainLongRaw, 
    file = "rawInput.txt", 
    sep = "\t", 
    row.names = FALSE, 
    quote = FALSE
)