# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "vartrix_consensus_snps.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "vartrix_consensus_snps.csv", row.names=FALSE)
# binary input "commonvariants_1kgenomes_subset.vcf": copy a real example from a Bioconductor ExperimentData pkg
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example commonvariants_1kgenomes_subset.vcf found in candidate data packages"=!is.na(.src))
file.copy(.src, "commonvariants_1kgenomes_subset.vcf", overwrite=TRUE)
# binary input "commonvariants_1kgenomes_subset.vcf.gz": copy a real example from a Bioconductor ExperimentData pkg
.src <- NA_character_
for (.dp in c("VariantAnnotation")) {
  if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.vcf(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example commonvariants_1kgenomes_subset.vcf.gz found in candidate data packages"=!is.na(.src))
file.copy(.src, "commonvariants_1kgenomes_subset.vcf", overwrite=TRUE)
