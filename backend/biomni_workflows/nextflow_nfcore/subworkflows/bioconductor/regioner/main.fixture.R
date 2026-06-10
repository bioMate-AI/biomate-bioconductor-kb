library(regioneR)

# Attempt to find and copy cpgHMM.txt from the installed package
cpg_candidates <- list.files(system.file(package="regioneR"), pattern="cpgHMM\\.txt$", recursive=TRUE, full.names=TRUE)
if (length(cpg_candidates) > 0 && file.exists(cpg_candidates[1])) {
    file.copy(cpg_candidates[1], "cpgHMM.txt", overwrite=TRUE)
} else {
    # Create a synthetic BED-like file for CpG islands if not found
    cpg_df <- data.frame(
        chr = c("chr1", "chr1", "chr2", "chr3"),
        start = c(10000, 25000, 15000, 40000),
        end = c(11000, 26000, 16000, 41000)
    )
    write.table(cpg_df, "cpgHMM.txt", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}

# Attempt to find and copy UCSC.promoters.hg19.bed from the installed package
promoters_candidates <- list.files(system.file(package="regioneR"), pattern="UCSC\\.promoters\\.hg19\\.bed$", recursive=TRUE, full.names=TRUE)
if (length(promoters_candidates) > 0 && file.exists(promoters_candidates[1])) {
    file.copy(promoters_candidates[1], "UCSC.promoters.hg19.bed", overwrite=TRUE)
} else {
    # Create a synthetic BED file for promoters if not found
    promoters_df <- data.frame(
        chr = c("chr1", "chr1", "chr2", "chr3"),
        start = c(10500, 30000, 14500, 50000),
        end = c(11500, 31000, 15500, 51000),
        name = c("PRM1", "PRM2", "PRM3", "PRM4"),
        score = c(1000, 1000, 1000, 1000),
        strand = c("+", "-", "+", "-")
    )
    write.table(promoters_df, "UCSC.promoters.hg19.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}