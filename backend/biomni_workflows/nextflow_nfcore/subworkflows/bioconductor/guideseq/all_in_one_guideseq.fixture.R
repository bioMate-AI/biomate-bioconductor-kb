# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "bowtie2.HEK293_site4_chr13.sort.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example bowtie2.HEK293_site4_chr13.sort.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "bowtie2.HEK293_site4_chr13.sort.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "bowtie2.HEK293_site4_chr13.sort.bam.bai", overwrite=TRUE)
# co-input "gRNA.fa": synthetic
writeLines(c(">seq1","ACGTACGTACGTACGTACGTACGTAGCTAGCTAGCTACG",">seq2","TTGGCCAATTGGCCAATTGGCCAATTGGCCAATTGGCCAA"), "gRNA.fa")
# co-input "UMI-HEK293_site4_chr13.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "UMI-HEK293_site4_chr13.txt", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "offTargets.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "offTargets.csv", row.names=FALSE)
# co-input "merged_peaks.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "merged_peaks.csv", row.names=FALSE)
# co-input "peaks.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "peaks.csv", row.names=FALSE)
# co-input "read_summary.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "read_summary.csv", row.names=FALSE)
