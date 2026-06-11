suppressPackageStartupMessages({
    library(RiboDiPA)
    library(Rsamtools)
})

# Create synthetic SAM content with reads mapping to chrIV
sam_header <- "@HD\tVN:1.0\tSO:coordinate\n@SQ\tSN:chrIV\tLN:1531933\n"
sam_records <- c(
    "r1\t0\tchrIV\t553166\t255\t28M\t*\t0\t0\tATGCATGCATGCATGCATGCATGCATGC\tIIIIIIIIIIIIIIIIIIIIIIIIIIII",
    "r2\t0\tchrIV\t553166\t255\t29M\t*\t0\t0\tATGCATGCATGCATGCATGCATGCATGCA\tIIIIIIIIIIIIIIIIIIIIIIIIIIIII",
    "r3\t0\tchrIV\t553166\t255\t30M\t*\t0\t0\tATGCATGCATGCATGCATGCATGCATGCAT\tIIIIIIIIIIIIIIIIIIIIIIIIIIIIII",
    "r4\t0\tchrIV\t553200\t255\t28M\t*\t0\t0\tATGCATGCATGCATGCATGCATGCATGC\tIIIIIIIIIIIIIIIIIIIIIIIIIIII",
    "r5\t0\tchrIV\t553210\t255\t29M\t*\t0\t0\tATGCATGCATGCATGCATGCATGCATGCA\tIIIIIIIIIIIIIIIIIIIIIIIIIIIII",
    "r6\t0\tchrIV\t553220\t255\t30M\t*\t0\t0\tATGCATGCATGCATGCATGCATGCATGCAT\tIIIIIIIIIIIIIIIIIIIIIIIIIIIIII"
)
sam_content <- paste0(sam_header, paste(sam_records, collapse="\n"), "\n")

# Write SAM files and convert to BAM
for (f in c("WT1", "WT2", "MUT1", "MUT2")) {
    sam_file <- paste0(f, ".sam")
    writeLines(sam_content, sam_file)
    asBam(sam_file, destination = f, overwrite = TRUE)
    unlink(sam_file)
}

# Create synthetic GTF file
gtf_content <- 'chrIV\tEnsembl\tgene\t553166\t554000\t.\t+\t.\tgene_id "YDR050C"; gene_name "TPI1";
chrIV\tEnsembl\ttranscript\t553166\t554000\t.\t+\t.\tgene_id "YDR050C"; transcript_id "YDR050C_tx";
chrIV\tEnsembl\texon\t553166\t554000\t.\t+\t.\tgene_id "YDR050C"; transcript_id "YDR050C_tx"; exon_number "1";
chrIV\tEnsembl\tstart_codon\t553166\t553168\t.\t+\t0\tgene_id "YDR050C"; transcript_id "YDR050C_tx"; exon_number "1";'
writeLines(gtf_content, "eg.gtf")

# Define the expected bam_path vector
bam_path <- c("WT1.bam", "WT2.bam", "MUT1.bam", "MUT2.bam", "eg.gtf")