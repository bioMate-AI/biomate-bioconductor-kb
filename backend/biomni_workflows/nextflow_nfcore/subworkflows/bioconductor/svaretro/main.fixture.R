# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "diploidSV.vcf": copy a real example from a Bioconductor ExperimentData pkg
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example diploidSV.vcf found in candidate data packages"=!is.na(.src))
file.copy(.src, "diploidSV.vcf", overwrite=TRUE)
# co-input "_junctions.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "_junctions.csv", row.names=FALSE)
# co-input "_insertion_sites.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "_insertion_sites.csv", row.names=FALSE)
