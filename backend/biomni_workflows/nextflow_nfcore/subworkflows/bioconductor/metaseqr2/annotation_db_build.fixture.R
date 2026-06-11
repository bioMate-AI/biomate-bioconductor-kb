# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz": synthetic
writeLines(c("chr1\tsrc\texon\t1000\t2000\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";"), "Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz")
# binary input "Dasnov3.broad.Ascending_Colon_5.1.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example Dasnov3.broad.Ascending_Colon_5.1.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "Dasnov3.broad.Ascending_Colon_5.1.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "Dasnov3.broad.Ascending_Colon_5.1.bam.bai", overwrite=TRUE)
# co-input "dasGenes.csv": synthetic
write.csv(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "dasGenes.csv", row.names=FALSE)
