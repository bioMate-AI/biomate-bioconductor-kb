# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "in.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "in.gtf")
# binary input "finbam.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example finbam.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "finbam.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "finbam.bam", overwrite=TRUE)
# co-input "fmdl.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "fmdl.gtf")
# co-input "ftgt.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "ftgt.gtf")
# binary input "intergenic_alignments.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example intergenic_alignments.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "intergenic_alignments.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "intergenic_alignments.bam.bai", overwrite=TRUE)
# co-input "predicted_models.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "predicted_models.gtf")
# co-input "selected_models.gtf": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "selected_models.gtf")
# co-input "fmdl.tsv": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "fmdl.tsv", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "ftgt.tsv": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "ftgt.tsv", sep="\t", row.names=FALSE, quote=FALSE)
