# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# co-input "reads_supporting_defuse_fusion_5267.1.fq": synthetic
writeLines(c("@r1","ACGTACGTACGTACGT","+","IIIIIIIIIIIIIIII","@r2","TTGGCCAATTGGCCAA","+","IIIIIIIIIIIIIIII"), "reads_supporting_defuse_fusion_5267.1.fq")
# co-input "reads_supporting_defuse_fusion_5267.2.fq": synthetic
writeLines(c("@r1","ACGTACGTACGTACGT","+","IIIIIIIIIIIIIIII","@r2","TTGGCCAATTGGCCAA","+","IIIIIIIIIIIIIIII"), "reads_supporting_defuse_fusion_5267.2.fq")
# co-input "reference.fa": synthetic
writeLines(c(">seq1","ACGTACGTACGTACGTACGTACGTAGCTAGCTAGCTACG",">seq2","TTGGCCAATTGGCCAATTGGCCAATTGGCCAATTGGCCAA"), "reference.fa")
# binary input "fusion_alignment.bam": copy a real example from a Bioconductor ExperimentData pkg
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools", "GenomicAlignments")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .src <- .f[[1]]; break }
  }
}
stopifnot("no example fusion_alignment.bam found in candidate data packages"=!is.na(.src))
file.copy(.src, "fusion_alignment.bam", overwrite=TRUE)
.bai <- paste0(.src, ".bai"); if (file.exists(.bai)) file.copy(.bai, "fusion_alignment.bam.bai", overwrite=TRUE)
# co-input "defuse_833ke_results.filtered.tsv": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "defuse_833ke_results.filtered.tsv", sep="\t", row.names=FALSE, quote=FALSE)
