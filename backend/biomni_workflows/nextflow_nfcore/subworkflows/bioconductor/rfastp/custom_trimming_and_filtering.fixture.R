library(Rfastp)

se_read1_src <- system.file("extdata", "Fox3_Std_small.fq.gz", package="Rfastp")

if (file.exists(se_read1_src)) {
    file.copy(se_read1_src, "se_read1", overwrite = TRUE)
} else {
    # Fallback: create a minimal synthetic gzipped FASTQ file if the package data is missing
    gz <- gzfile("se_read1", "w")
    writeLines(c(
        "@SEQ_ID",
        "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT",
        "+",
        "!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65"
    ), gz)
    close(gz)
}