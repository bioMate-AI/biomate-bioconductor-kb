library(RCAS)

# Find and copy BED file
bed_candidates <- c(
    system.file("extdata", "query_regions.bed", package = "RCAS"),
    system.file("extdata", "FUS_Nakaya2013c_hg19.bed", package = "RCAS"),
    list.files(system.file("extdata", package = "RCAS"), pattern = "\\.bed$", full.names = TRUE)
)
bed_candidates <- bed_candidates[file.exists(bed_candidates)]

if (length(bed_candidates) > 0) {
    file.copy(bed_candidates[1], "queryRegions.bed", overwrite = TRUE)
} else {
    # Synthetic fallback
    writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+"), "queryRegions.bed")
}

# Find and copy GTF file
gtf_candidates <- c(
    system.file("extdata", "annotation.gtf", package = "RCAS"),
    system.file("extdata", "hg19.sample.gtf", package = "RCAS"),
    list.files(system.file("extdata", package = "RCAS"), pattern = "\\.gtf$", full.names = TRUE)
)
gtf_candidates <- gtf_candidates[file.exists(gtf_candidates)]

if (length(gtf_candidates) > 0) {
    file.copy(gtf_candidates[1], "annotation.gtf", overwrite = TRUE)
} else {
    # Synthetic fallback
    writeLines(c("chr1\tRCAS\tgene\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "annotation.gtf")
}