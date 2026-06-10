# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "query_mat.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "query_mat.csv", row.names=FALSE)
# co-input "upset.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "upset.txt", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "downset.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "downset.txt", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "db_path.txt": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "db_path.txt", sep="\t", row.names=FALSE, quote=FALSE)
# binary input "database.h5": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("rhdf5", "HDF5Array")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("rhdf5", "HDF5Array")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.h5$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example database.h5 found in candidate data packages"=!is.na(.src))
file.copy(.src, "database.h5", overwrite=TRUE)
