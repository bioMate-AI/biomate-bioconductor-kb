write.table(
    data.frame(
        chrom = c("chr1", "chr1", "chr2"),
        start = c(10000, 20000, 30000),
        end = c(15000, 25000, 35000),
        name = c("region1", "region2", "region3"),
        score = c(0, 0, 0),
        strand = c("+", "-", "+")
    ),
    file = "regions.bed",
    sep = "\t",
    quote = FALSE,
    row.names = FALSE,
    col.names = FALSE
)

write.csv(
    data.frame(
        sample = c("sample1", "sample2", "sample3"),
        condition = c("control", "treatment", "treatment")
    ),
    file = "coldata.csv",
    row.names = FALSE,
    quote = FALSE
)