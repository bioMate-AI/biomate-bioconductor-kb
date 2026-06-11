# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "reference.fa": synthetic
writeLines(c(">seq1","ACGTACGTACGTACGTACGTACGTAGCTAGCTAGCTACG",">seq2","TTGGCCAATTGGCCAATTGGCCAATTGGCCAATTGGCCAA"), "reference.fa")
# binary input "tumor.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example tumor.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "tumor.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "tumor.bam.bai", overwrite=TRUE)
# binary input "normal_panel.vcf": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("VariantAnnotation")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example normal_panel.vcf found in candidate data packages"=!is.na(.src))
file.copy(.src, "normal_panel.vcf", overwrite=TRUE)
# binary input "tumor_mutect.vcf": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("VariantAnnotation")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example tumor_mutect.vcf found in candidate data packages"=!is.na(.src))
file.copy(.src, "tumor_mutect.vcf", overwrite=TRUE)
# co-input "baits.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "baits.bed")
# co-input "ex2_gc_file.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "ex2_gc_file.txt", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "ex1_coverage.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "ex1_coverage.txt", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "tumor_coverage_loess.txt.gz": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "tumor_coverage_loess.txt.gz", sep="\t", row.names=FALSE, quote=FALSE)
