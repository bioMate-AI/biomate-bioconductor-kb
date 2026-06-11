library(metaseqR2)
library(Rsamtools)

# 1. Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz
gtf_file <- list.files(system.file(package="metaseqR2"), pattern="Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz", recursive=TRUE, full.names=TRUE)
if (length(gtf_file) > 0) {
    file.copy(gtf_file[1], "Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz")
} else {
    gtf_content <- c(
        '1\tensembl\tgene\t1000\t2000\t.\t+\t.\tgene_id "ENSG000001"; gene_name "GENE1";',
        '1\tensembl\ttranscript\t1000\t2000\t.\t+\t.\tgene_id "ENSG000001"; transcript_id "ENST000001";',
        '1\tensembl\texon\t1000\t1200\t.\t+\t.\tgene_id "ENSG000001"; transcript_id "ENST000001"; exon_number "1";',
        '1\tensembl\texon\t1800\t2000\t.\t+\t.\tgene_id "ENSG000001"; transcript_id "ENST000001"; exon_number "2";'
    )
    gz1 <- gzfile("Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz", "w")
    writeLines(gtf_content, gz1)
    close(gz1)
}

# 2. bamForInfo
bam_file <- list.files(system.file(package="metaseqR2"), pattern="bamForInfo", recursive=TRUE, full.names=TRUE)
if (length(bam_file) > 0) {
    file.copy(bam_file[1], "bamForInfo")
} else {
    sam_content <- c(
        "@HD\tVN:1.4\tSO:coordinate",
        "@SQ\tSN:1\tLN:10000",
        "read1\t0\t1\t1000\t255\t100M\t*\t0\t0\t*\t*"
    )
    writeLines(sam_content, "dummy.sam")
    asBam("dummy.sam", destination="bamForInfo", overwrite=TRUE)
    if (file.exists("bamForInfo.bam")) {
        file.rename("bamForInfo.bam", "bamForInfo")
    }
    if (file.exists("bamForInfo.bam.bai")) {
        file.rename("bamForInfo.bam.bai", "bamForInfo.bai")
    }
}