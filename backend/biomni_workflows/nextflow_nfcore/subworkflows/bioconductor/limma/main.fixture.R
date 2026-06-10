# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "array1.gpr": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("marray", "limma")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("marray", "limma")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.gpr$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example array1.gpr found in candidate data packages"=!is.na(.src))
file.copy(.src, "array1.gpr", overwrite=TRUE)
# binary input "array2.gpr": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("marray", "limma")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("marray", "limma")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.gpr$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example array2.gpr found in candidate data packages"=!is.na(.src))
file.copy(.src, "array2.gpr", overwrite=TRUE)
# binary input "array3.gpr": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("marray", "limma")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("marray", "limma")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.gpr$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example array3.gpr found in candidate data packages"=!is.na(.src))
file.copy(.src, "array3.gpr", overwrite=TRUE)
# binary input "array4.gpr": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("marray", "limma")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("marray", "limma")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.gpr$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example array4.gpr found in candidate data packages"=!is.na(.src))
file.copy(.src, "array4.gpr", overwrite=TRUE)
# co-input "targets.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "targets.txt", sep="\t", row.names=FALSE, quote=FALSE)
