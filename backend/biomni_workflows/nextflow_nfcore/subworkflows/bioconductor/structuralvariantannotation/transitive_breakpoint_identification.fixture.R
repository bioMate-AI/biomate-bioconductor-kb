# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "truthset_somaticSVs_COLO829.vcf": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("VariantAnnotation")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example truthset_somaticSVs_COLO829.vcf found in candidate data packages"=!is.na(.src))
file.copy(.src, "truthset_somaticSVs_COLO829.vcf", overwrite=TRUE)
# binary input "colo829_nanoSV_truth_overlap.vcf": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("VariantAnnotation")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example colo829_nanoSV_truth_overlap.vcf found in candidate data packages"=!is.na(.src))
file.copy(.src, "colo829_nanoSV_truth_overlap.vcf", overwrite=TRUE)
# co-input "transitive_calls.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "transitive_calls.csv", row.names=FALSE)
