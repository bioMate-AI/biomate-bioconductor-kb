# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "user_data.fcs": first non-text file in the pkg extdata (example has no ext)
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
stopifnot("no example user_data.fcs found in candidate data packages"=!is.na(.src))
file.copy(.src, "user_data.fcs", overwrite=TRUE)
