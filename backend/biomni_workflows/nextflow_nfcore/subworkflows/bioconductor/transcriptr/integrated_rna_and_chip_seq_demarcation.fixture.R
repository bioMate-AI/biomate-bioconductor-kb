# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "path.to.Bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example path.to.Bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "path.to.Bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "path.to.Bam.bai", overwrite=TRUE)
# co-input "transcripts.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "transcripts.bed")
# co-input "classification_performance.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "classification_performance.txt", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "peaks.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "peaks.bed")
# co-input "transcripts_final.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "transcripts_final.bed")
