# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "example_dt.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "example_dt.csv", row.names=FALSE)
# co-input "example_dt.tsv": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "example_dt.tsv", sep="\t", row.names=FALSE, quote=FALSE)
# binary input "chr22.vcf.gz": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("VariantAnnotation")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example chr22.vcf.gz found in candidate data packages"=!is.na(.src))
file.copy(.src, "chr22.vcf.gz", overwrite=TRUE)
