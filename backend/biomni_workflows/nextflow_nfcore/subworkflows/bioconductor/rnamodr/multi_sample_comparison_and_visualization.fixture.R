# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "RNAmodR.Data.example.AAS.gff3": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "RNAmodR.Data.example.AAS.gff3")
# co-input "RNAmodR.Data.example.AAS.fasta": synthetic
writeLines(c(">seq1","ACGTACGTACGTACGTACGTACGTAGCTAGCTAGCTACG",">seq2","TTGGCCAATTGGCCAATTGGCCAATTGGCCAATTGGCCAA"), "RNAmodR.Data.example.AAS.fasta")
# binary input "wt_1.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example wt_1.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "wt_1.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "wt_1.bam.bai", overwrite=TRUE)
# binary input "wt_2.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example wt_2.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "wt_2.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "wt_2.bam.bai", overwrite=TRUE)
# binary input "wt_3.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example wt_3.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "wt_3.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "wt_3.bam.bai", overwrite=TRUE)
# binary input "bud23_1.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example bud23_1.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "bud23_1.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "bud23_1.bam.bai", overwrite=TRUE)
# binary input "bud23_2.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example bud23_2.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "bud23_2.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "bud23_2.bam.bai", overwrite=TRUE)
# binary input "trm8_1.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example trm8_1.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "trm8_1.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "trm8_1.bam.bai", overwrite=TRUE)
# binary input "trm8_2.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example trm8_2.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "trm8_2.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "trm8_2.bam.bai", overwrite=TRUE)
# co-input "comparison_by_coordinate.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "comparison_by_coordinate.csv", row.names=FALSE)
