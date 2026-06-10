# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "defIgRanges_in.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "defIgRanges_in.gtf")
# binary input "CMPRep2.sortedByCoord.raw.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example CMPRep2.sortedByCoord.raw.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "CMPRep2.sortedByCoord.raw.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "CMPRep2.sortedByCoord.raw.bam.bai", overwrite=TRUE)
# binary input "CMPRep2_intergenic.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example CMPRep2_intergenic.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "CMPRep2_intergenic.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "CMPRep2_intergenic.bam.bai", overwrite=TRUE)
# co-input "predicted_models.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "predicted_models.gtf")
# co-input "selModel_in.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "selModel_in.gtf")
# co-input "selected_models.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "selected_models.gtf")
# co-input "plcf.tsv": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "plcf.tsv", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "tgt.tsv": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "tgt.tsv", sep="\t", row.names=FALSE, quote=FALSE)
