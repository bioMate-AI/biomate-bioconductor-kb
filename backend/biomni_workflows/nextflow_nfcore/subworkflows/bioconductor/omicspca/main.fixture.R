suppressPackageStartupMessages({
    library(OMICsPCA)
    library(OMICsPCAdata)
})

# Locate the files from the companion data package as described in the vignette
anno_path <- system.file("extdata/annotation2/TSS_groups.bed", package = "OMICsPCAdata")
list_path <- system.file("extdata/annotation2/TSS_list", package = "OMICsPCAdata")
fact_path <- system.file("extdata/factors2/demofactor", package = "OMICsPCAdata")

# 1. Prepare annofile.bed
if (file.exists(anno_path) && nzchar(anno_path)) {
    file.copy(anno_path, "annofile.bed", overwrite = TRUE)
} else {
    # Fallback to synthetic data matching the vignette's description
    write.table(data.frame(
        chromosome = c("chr1", "chr1", "chr1", "chr1", "chr1"),
        start = c(11858, 11999, 29543, 30256, 53038),
        end = c(11885, 12021, 29565, 30278, 53060),
        TSS_ID = c("TSS1", "TSS2", "TSS3", "TSS4", "TSS5")
    ), "annofile.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

# 2. Prepare annolist.txt
if (file.exists(list_path) && nzchar(list_path)) {
    file.copy(list_path, "annolist.txt", overwrite = TRUE)
} else {
    # Fallback to synthetic data matching the vignette's description
    writeLines(c("TSS1", "TSS2", "TSS3", "TSS4", "TSS5"), "annolist.txt")
}

# 3. Prepare factdir and its contents
dir.create("factdir", showWarnings = FALSE)
if (file.exists(fact_path) && nzchar(fact_path) && length(list.files(fact_path)) > 0) {
    bed_files <- list.files(fact_path, full.names = TRUE)
    file.copy(bed_files, "factdir/", overwrite = TRUE)
} else {
    # Fallback to synthetic data matching the vignette's description
    write.table(data.frame(
        chromosome = c("chr1", "chr1", "chr1", "chr1", "chr1"),
        start = c(29533, 53000, 160430, 893924, 895275),
        end = c(29590, 53010, 160467, 895151, 896888),
        intensity = c(3.665498, 3.798148, 4.294974, 3.160494, 3.881008)
    ), "factdir/Cell1.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
    
    write.table(data.frame(
        chromosome = c("chr1", "chr1", "chr1", "chr1", "chr1"),
        start = c(29533, 53000, 160430, 893924, 895275),
        end = c(29590, 53010, 160467, 895151, 896888),
        intensity = c(0, 1.86, 0, 0, 0)
    ), "factdir/Cell2.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}