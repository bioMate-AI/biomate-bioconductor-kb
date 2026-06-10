# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "input.vcf": copy a real example from a Bioconductor ExperimentData pkg
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example input.vcf found in candidate data packages"=!is.na(.src))
file.copy(.src, "input.vcf", overwrite=TRUE)
# co-input "hgvs_annotations.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "hgvs_annotations.csv", row.names=FALSE)
# co-input "rsid_annotations.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "rsid_annotations.csv", row.names=FALSE)
