library(Rfastp)

files_to_copy <- list(
    pe001_read1 = "splited_001_R1.fastq.gz",
    pe002_read1 = "splited_002_R1.fastq.gz",
    pe003_read1 = "splited_003_R1.fastq.gz",
    pe004_read1 = "splited_004_R1.fastq.gz",
    pe001_read2 = "splited_001_R2.fastq.gz",
    pe002_read2 = "splited_002_R2.fastq.gz",
    pe003_read2 = "splited_003_R2.fastq.gz",
    pe004_read2 = "splited_004_R2.fastq.gz"
)

for (dest in names(files_to_copy)) {
    src <- system.file("extdata", files_to_copy[[dest]], package="Rfastp")
    if (file.exists(src)) {
        file.copy(src, dest, overwrite = TRUE)
    } else {
        # Fallback to a minimal valid FASTQ if the package data is missing
        gz <- gzfile(dest, "w")
        writeLines(c(
            "@SEQ_ID",
            "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT",
            "+",
            "!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65"
        ), gz)
        close(gz)
    }
}