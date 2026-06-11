# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("simPIC")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(simPIC)

# 1. Generate singlecell.csv (Cell barcodes with metadata)
singlecell_data <- data.frame(
  barcode = c("GTCACAAGTGGCATAG-1", "CCATACCGTGAGGGTT-1", "AACAAAGGTCGTAGTT-1", "ATTGTGGTCGATGTGT-1", "TCTATTGGTCTGGGAA-1"),
  cell_type = c("TypeA", "TypeB", "TypeA", "TypeB", "TypeA")
)
write.csv(singlecell_data, "singlecell.csv", row.names = FALSE, quote = FALSE)

# 2. Generate peaks.bed (List of peak regions)
peaks_data <- data.frame(
  chrom = c("chr11", "chr1", "chr2", "chr18", "chr10"),
  chromStart = c(3622698, 40703222, 21316881, 3411756, 12446853),
  chromEnd = c(3623526, 40703996, 21317790, 3412657, 12447562)
)
write.table(peaks_data, "peaks.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# 3. Generate fragment.tsv.gz (Fragment files)
fragment_data <- data.frame(
  chrom = c("chr11", "chr10"),
  chromStart = c(3622700, 12446900),
  chromEnd = c(3622800, 12447000),
  barcode = c("GTCACAAGTGGCATAG-1", "ATTGTGGTCGATGTGT-1"),
  readCount = c(1, 1)
)
gz_con <- gzfile("fragment.tsv.gz", "w")
write.table(fragment_data, gz_con, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
close(gz_con)