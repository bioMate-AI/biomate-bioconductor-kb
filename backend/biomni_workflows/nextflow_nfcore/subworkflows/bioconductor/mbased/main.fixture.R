# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MBASED", "GenomicRanges", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MBASED)
library(GenomicRanges)
library(SummarizedExperiment)

# Recreate the GRanges object for SNVs of interest from the vignette
mySNVs <- GRanges(
  seqnames=c('chr1', 'chr2', 'chr2', 'chr2'),
  ranges=IRanges(start=c(100, 1000, 1100, 1200), width=1),
  aseID=c('gene1', rep('gene2', 3)),
  allele1=c('G', 'A', 'C', 'A'),
  allele2=c('T', 'C', 'T', 'G')	
)
names(mySNVs) <- c('gene1_SNV1', 'gene2_SNV1', 'gene2_SNV2', 'gene2_SNV3')

# Serialize to snv_coordinates.bed
snv_df <- data.frame(
  chrom = as.character(seqnames(mySNVs)),
  start = start(mySNVs) - 1, # BED format is 0-based
  end = end(mySNVs),
  name = names(mySNVs),
  score = 0,
  strand = as.character(strand(mySNVs)),
  aseID = mySNVs$aseID,
  allele1 = mySNVs$allele1,
  allele2 = mySNVs$allele2,
  stringsAsFactors = FALSE
)
write.table(snv_df, "snv_coordinates.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)

# Serialize to rna_seq_counts.tsv
# Using the counts from the vignette's mySample SummarizedExperiment
counts_df <- data.frame(
  SNV = names(mySNVs),
  allele1_counts = c(25, 10, 22, 14),
  allele2_counts = c(20, 16, 15, 16),
  stringsAsFactors = FALSE
)
write.table(counts_df, "rna_seq_counts.tsv", sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)