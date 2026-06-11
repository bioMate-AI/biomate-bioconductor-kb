# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "sample_key.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "sample_key.csv", row.names=FALSE)
# binary input "raw_data.fcs": first non-text file in the pkg extdata (example has no ext)
for (.dp in c("flowCore")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("flowCore")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, recursive=TRUE, full.names=TRUE)
    .f <- .f[!grepl("(?i)\\.(txt|csv|tsv|md|rds|rda|r|html?|pdf|xml|json)$|README", .f)]
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example raw_data.fcs found in candidate data packages"=!is.na(.src))
file.copy(.src, "raw_data.fcs", overwrite=TRUE)
# binary input "sample_ff.fcs": first non-text file in the pkg extdata (example has no ext)
for (.dp in c("flowCore")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("flowCore")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, recursive=TRUE, full.names=TRUE)
    .f <- .f[!grepl("(?i)\\.(txt|csv|tsv|md|rds|rda|r|html?|pdf|xml|json)$|README", .f)]
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example sample_ff.fcs found in candidate data packages"=!is.na(.src))
file.copy(.src, "sample_ff.fcs", overwrite=TRUE)
# binary input "ss_exp.fcs": first non-text file in the pkg extdata (example has no ext)
for (.dp in c("flowCore")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("flowCore")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, recursive=TRUE, full.names=TRUE)
    .f <- .f[!grepl("(?i)\\.(txt|csv|tsv|md|rds|rda|r|html?|pdf|xml|json)$|README", .f)]
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example ss_exp.fcs found in candidate data packages"=!is.na(.src))
file.copy(.src, "ss_exp.fcs", overwrite=TRUE)
# binary input "mp_cells.fcs": first non-text file in the pkg extdata (example has no ext)
for (.dp in c("flowCore")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("flowCore")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, recursive=TRUE, full.names=TRUE)
    .f <- .f[!grepl("(?i)\\.(txt|csv|tsv|md|rds|rda|r|html?|pdf|xml|json)$|README", .f)]
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example mp_cells.fcs found in candidate data packages"=!is.na(.src))
file.copy(.src, "mp_cells.fcs", overwrite=TRUE)
