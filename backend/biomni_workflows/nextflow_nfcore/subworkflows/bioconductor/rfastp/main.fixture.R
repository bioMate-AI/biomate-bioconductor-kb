library(Rfastp)

se_read1_src <- system.file("extdata", "Fox3_Std_small.fq.gz", package="Rfastp")

if (file.exists(se_read1_src)) {
    file.copy(from = se_read1_src, to = "Fox3_Std_small.fq.gz", overwrite = TRUE)
} else {
    stop("Required input file Fox3_Std_small.fq.gz not found in Rfastp package.")
}