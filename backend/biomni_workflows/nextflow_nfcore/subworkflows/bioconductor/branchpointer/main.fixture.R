library(branchpointer)

# 1. gencode.v26.annotation.gtf
gtf_src <- system.file("extdata", "gencode.v26.annotation.small.gtf", package = "branchpointer")
if (file.exists(gtf_src)) {
    file.copy(gtf_src, "gencode.v26.annotation.gtf", overwrite = TRUE)
} else {
    gtf_files <- list.files(system.file("extdata", package = "branchpointer"), pattern = "\\.gtf$", full.names = TRUE)
    if (length(gtf_files) > 0) {
        file.copy(gtf_files[1], "gencode.v26.annotation.gtf", overwrite = TRUE)
    } else {
        # Fallback: Create a minimal dummy GTF if not found
        dummy_gtf <- c(
            "chr17\tHAVANA\texon\t43045820\t43045846\t.\t-\t.\tgene_id \"ENSG00000012048.21\"; transcript_id \"ENST00000357654.8\"; exon_number 1; exon_id \"ENSE00003512345.1\";",
            "chr13\tHAVANA\texon\t32346783\t32346809\t.\t+\t.\tgene_id \"ENSG00000139618.15\"; transcript_id \"ENST00000380152.7\"; exon_number 1; exon_id \"ENSE00003512346.1\";"
        )
        writeLines(dummy_gtf, "gencode.v26.annotation.gtf")
    }
}

# 2. intron_example.txt
intron_src <- system.file("extdata", "intron_example.txt", package = "branchpointer")
if (file.exists(intron_src)) {
    file.copy(intron_src, "intron_example.txt", overwrite = TRUE)
} else {
    # Fallback: Create the exact table from the vignette
    intron_data <- data.frame(
        id = c("BRCA1_intron", "BRCA2_intron"),
        chromosome = c("chr17", "chr13"),
        start = c(43045820, 32346783),
        end = c(43045846, 32346809),
        strand = c("-", "+")
    )
    write.table(intron_data, "intron_example.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}