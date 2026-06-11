# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "N01.fasta": synthetic
writeLines(c(">seq1","ACGTACGTACGTACGTACGTACGTAGCTAGCTAGCTACG",">seq2","TTGGCCAATTGGCCAATTGGCCAATTGGCCAATTGGCCAA"), "N01.fasta")
# binary input "N01.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example N01.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "N01.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "N01.bam.bai", overwrite=TRUE)
# co-input "CaptureArray_hg19.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "CaptureArray_hg19.bed")
# co-input "merged_breakpoints_summary.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "merged_breakpoints_summary.txt", sep="\t", row.names=FALSE, quote=FALSE)
