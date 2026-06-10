library(QuasR)
library(rtracklayer)

# 1. hg19sub.fa
hg19sub_path <- system.file("extdata", "hg19sub.fa", package="QuasR")
if (file.exists(hg19sub_path)) {
    file.copy(hg19sub_path, "hg19sub.fa", overwrite = TRUE)
} else {
    writeLines(c(">chr1", "ACGTACGTACGT"), "hg19sub.fa")
}

# 2. samples_mirna.txt
samples_mirna_path <- system.file("extdata", "samples_mirna.txt", package="QuasR")
if (file.exists(samples_mirna_path)) {
    file.copy(samples_mirna_path, "samples_mirna.txt", overwrite = TRUE)
} else {
    sample_df <- data.frame(
        FileName = "mirna_1.fasta",
        SampleName = "Sample1"
    )
    write.table(sample_df, "samples_mirna.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# 3. mirbaseXX_qsr.gff3
gff_path <- system.file("extdata", "mirbaseXX_qsr.gff3", package="QuasR")
if (file.exists(gff_path)) {
    file.copy(gff_path, "mirbaseXX_qsr.gff3", overwrite = TRUE)
} else {
    gff3_content <- c(
        "##gff-version 3",
        "chr1\tmirbase\tmiRNA\t100\t200\t.\t+\t.\tID=mir1;Name=hsa-miR-1"
    )
    writeLines(gff3_content, "mirbaseXX_qsr.gff3")
}