# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "chr1.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example chr1.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "chr1.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "chr1.bam.bai", overwrite=TRUE)
# co-input "chr1.fastq.gz": synthetic
writeLines(c("@r1","ACGTACGTACGTACGT","+","IIIIIIIIIIIIIIII","@r2","TTGGCCAATTGGCCAA","+","IIIIIIIIIIIIIIII"), "chr1.fastq.gz")
# co-input "count_ALL_chr22.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "count_ALL_chr22.txt", sep="\t", row.names=FALSE, quote=FALSE)
