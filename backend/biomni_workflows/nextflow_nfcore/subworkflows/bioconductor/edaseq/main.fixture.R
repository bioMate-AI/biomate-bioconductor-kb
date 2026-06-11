# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "file1.fastq": synthetic
writeLines(c("@r1","ACGTACGTACGTACGT","+","IIIIIIIIIIIIIIII","@r2","TTGGCCAATTGGCCAA","+","IIIIIIIIIIIIIIII"), "file1.fastq")
# binary input "file2.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example file2.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "file2.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "file2.bam.bai", overwrite=TRUE)
# co-input "fastq_metadata.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "fastq_metadata.csv", row.names=FALSE)
# co-input "bam_metadata.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "bam_metadata.csv", row.names=FALSE)
