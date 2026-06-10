# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "raw_arrays.CEL": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("affydata", "SpikeInSubset", "affydatadnacopy")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("affydata", "SpikeInSubset", "affydatadnacopy")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.cel(\\.gz)?$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example raw_arrays.CEL found in candidate data packages"=!is.na(.src))
file.copy(.src, "raw_arrays.CEL", overwrite=TRUE)
# co-input "outlier_details_by_alpha.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "outlier_details_by_alpha.txt", sep="\t", row.names=FALSE, quote=FALSE)
