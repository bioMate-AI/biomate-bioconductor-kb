# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "sample.fcs": first non-text file in the pkg extdata (example has no ext)
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
stopifnot("no example sample.fcs found in candidate data packages"=!is.na(.src))
file.copy(.src, "sample.fcs", overwrite=TRUE)
# co-input "lymphocyte_locations.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "lymphocyte_locations.csv", row.names=FALSE)
