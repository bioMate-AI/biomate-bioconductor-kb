library(branchpointer)

# 1. Prepare gencode.v26.annotation.gtf
# The vignette uses a small GTF shipped with the package. We copy it to the expected filename.
gtf_src <- system.file("extdata", "gencode.v26.annotation.small.gtf", package = "branchpointer")
if (file.exists(gtf_src)) {
    file.copy(gtf_src, "gencode.v26.annotation.gtf", overwrite = TRUE)
} else {
    # Fallback to any GTF in extdata if the exact name changed
    gtf_files <- list.files(system.file("extdata", package = "branchpointer"), pattern = "\\.gtf$", full.names = TRUE)
    if (length(gtf_files) > 0) {
        file.copy(gtf_files[1], "gencode.v26.annotation.gtf", overwrite = TRUE)
    } else {
        stop("No GTF file found in branchpointer extdata")
    }
}

# 2. Prepare SNP_example.txt
# The vignette uses this exact file from extdata.
snp_src <- system.file("extdata", "SNP_example.txt", package = "branchpointer")
if (file.exists(snp_src)) {
    file.copy(snp_src, "SNP_example.txt", overwrite = TRUE)
} else {
    # Fallback: construct a synthetic file matching the ground truth specification
    snp_data <- data.frame(
        id = c("rs587776767", "rs786205083"),
        chromosome = c("chr17", "chr13"),
        chrom_start = c(43045820, 32346783),
        strand = c("-", "+"),
        ref_allele = c("A", "C"),
        alt_allele = c("G", "T")
    )
    write.table(snp_data, "SNP_example.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}