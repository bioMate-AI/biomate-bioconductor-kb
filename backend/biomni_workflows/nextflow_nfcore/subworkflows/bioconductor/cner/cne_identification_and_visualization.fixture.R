library(CNEr)

# 1. hg38.danRer10.net.axt
axt1 <- file.path(system.file("extdata", package="CNEr"), "hg38.danRer10.net.axt")
if (file.exists(axt1)) {
    file.copy(axt1, "hg38.danRer10.net.axt", overwrite = TRUE)
} else {
    writeLines(c(
        "0 chr1 148165963 148166304 chr6 25825774 25826099 + 5310",
        "TCTCTCCCATCCCAACTGTTCTAAATGTTCTTCCATTTGCAGCTCTTTTCCAACCAAAACAACAGAAATTAAACTT",
        "TTTCTCTCCTGCTAGGTTTTATAAGAGTGTTTTTCAGTTTCGGGTGCCTTTTCAGAGTAATGAGGGAAATTAAATTT",
        ""
    ), "hg38.danRer10.net.axt")
}

# 2. danRer10.hg38.net.axt
axt2 <- file.path(system.file("extdata", package="CNEr"), "danRer10.hg38.net.axt")
if (file.exists(axt2)) {
    file.copy(axt2, "danRer10.hg38.net.axt", overwrite = TRUE)
} else {
    writeLines(c(
        "0 chr6 24000620 24001357 chr7 146767015 146767753 - -4315",
        "GCGGATTTATGTAGAAAGATTTTTGGGAGTATCATAAATAGAGCCACAATTCTCATTCAGCTATGTGTAGGGTTATT",
        "GAGGGCCAGTCTGGAAAGCTAACTAGGAGGATGCCAAAAGAGAAAGGGATTCATAATGGAAACTGAGGGAGCTGCTT",
        ""
    ), "danRer10.hg38.net.axt")
}

# 3. filter_regions.danRer10.bed
bed1 <- file.path(system.file("extdata", package="CNEr"), "filter_regions.danRer10.bed")
if (file.exists(bed1)) {
    file.copy(bed1, "filter_regions.danRer10.bed", overwrite = TRUE)
} else {
    write.table(
        data.frame(
            chrom = c("chr6", "chr6"),
            chromStart = c(24000000, 25000000),
            chromEnd = c(24001000, 25001000)
        ),
        file = "filter_regions.danRer10.bed",
        sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE
    )
}

# 4. filter_regions.hg38.bed
bed2 <- file.path(system.file("extdata", package="CNEr"), "filter_regions.hg38.bed")
if (file.exists(bed2)) {
    file.copy(bed2, "filter_regions.hg38.bed", overwrite = TRUE)
} else {
    write.table(
        data.frame(
            chrom = c("chr1", "chr1"),
            chromStart = c(148165000, 222131000),
            chromEnd = c(148166000, 222132000)
        ),
        file = "filter_regions.hg38.bed",
        sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE
    )
}