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

# Recreate the GRanges object for SNVs from the vignette
mySNVs_2s <- GRanges(
  seqnames=c('chr1', 'chr2', 'chr2', 'chr2', 'chr3'),
  ranges=IRanges(start=c(100, 1000, 1100, 1200, 2000), width=1),
  aseID=c('gene1', rep('gene2', 3), 'gene3'),
  allele1=c('G', 'A', 'C', 'A', 'T'),
  allele2=c('T', 'C', 'T', 'G', 'G')	
)
names(mySNVs_2s) <- c('gene1_SNV1', 'gene2_SNV1', 'gene2_SNV2', 'gene2_SNV3', 'gene3_SNV1')

# Serialize to snv_coordinates.bed
bed_df <- data.frame(
  chrom = as.character(seqnames(mySNVs_2s)),
  chromStart = start(mySNVs_2s) - 1,
  chromEnd = end(mySNVs_2s),
  name = names(mySNVs_2s),
  score = 0,
  strand = as.character(strand(mySNVs_2s)),
  aseID = mySNVs_2s$aseID,
  allele1 = mySNVs_2s$allele1,
  allele2 = mySNVs_2s$allele2
)
write.table(bed_df, "snv_coordinates.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)

# Recreate the allele counts from the vignette and serialize to rna_seq_counts_two_samples.tsv
counts_df <- data.frame(
  SNV = names(mySNVs_2s),
  tumor_allele1 = c(25, 10, 35, 14, 35),
  tumor_allele2 = c(20, 29, 15, 40, 9),
  normal_allele1 = c(18, 17, 21, 25, 40),
  normal_allele2 = c(23, 19, 24, 31, 10)
)
write.table(counts_df, "rna_seq_counts_two_samples.tsv", sep="\t", quote=FALSE, row.names=FALSE)