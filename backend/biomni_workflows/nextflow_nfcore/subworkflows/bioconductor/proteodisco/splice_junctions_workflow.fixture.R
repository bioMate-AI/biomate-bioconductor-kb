library(ProteoDisco)
library(readr)

# 1. spliceJunctions_pyQUILTS_chr22.bed
bed_candidates <- list.files(system.file("extdata", package="ProteoDisco"), 
                             pattern="spliceJunctions_pyQUILTS_chr22\\.bed$", 
                             recursive=TRUE, full.names=TRUE)
if (length(bed_candidates) > 0) {
    file.copy(bed_candidates[1], "spliceJunctions_pyQUILTS_chr22.bed", overwrite = TRUE)
} else {
    # Fallback synthetic BED file
    writeLines(c("chr22\t17000000\t17000100\tJUNC1\t0\t+"), "spliceJunctions_pyQUILTS_chr22.bed")
}

# 2. validationSetSJ_hg19.txt
txt_candidates <- list.files(system.file("extdata", package="ProteoDisco"), 
                             pattern="validationSetSJ_hg19\\.txt$", 
                             recursive=TRUE, full.names=TRUE)
if (length(txt_candidates) > 0) {
    file.copy(txt_candidates[1], "validationSetSJ_hg19.txt", overwrite = TRUE)
} else {
    # Fallback synthetic TSV file
    sj_data <- data.frame(
        seqnames = "chr22",
        start = 17000000,
        end = 17000100,
        strand = "+",
        sample = "sample1"
    )
    write.table(sj_data, "validationSetSJ_hg19.txt", sep="\t", row.names=FALSE, quote=FALSE)
}