library(ribosomeProfilingQC)

extdata_dir <- system.file("extdata", package = "ribosomeProfilingQC")

rpf_files <- c("RPF.WT.1.bam", "RPF.WT.2.bam", "RPF.KD1.1.bam", "RPF.KD1.2.bam")
rna_files <- c("mRNA.WT.1.bam", "mRNA.WT.2.bam", "mRNA.KD1.1.bam", "mRNA.KD1.2.bam")
gtf_file <- "Danio_rerio.GRCz10.91.chr1.gtf.gz"

# Copy the actual BAM and GTF files to the working directory
for (f in c(rpf_files, rna_files, gtf_file)) {
    src <- file.path(extdata_dir, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    }
    # Also copy index files if they exist
    bai_src <- paste0(src, ".bai")
    if (file.exists(bai_src)) {
        file.copy(bai_src, paste0(f, ".bai"), overwrite = TRUE)
    }
}

# Serialize the vectors of file paths to the declared input files
saveRDS(rpf_files, "RPFs")
saveRDS(rna_files, "RNAs")
saveRDS(gtf_file, "gtf")