# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("chromPlot", "TxDb.Hsapiens.UCSC.hg19.knownGene", "GenomicFeatures")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("chromPlot")
library("TxDb.Hsapiens.UCSC.hg19.knownGene")
library("GenomicFeatures")

# Reproduce data-preparation code for hg_gap
data(hg_gap)

# Reproduce data-preparation code for txgr
txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
txgr <- transcripts(txdb)

# Reproduce data-preparation code for refGeneHg
data_file1       <- system.file("extdata", "hg19_refGeneChr19-21.txt", package = "chromPlot")
refGeneHg        <- read.table(data_file1, sep="\t", header=TRUE, stringsAsFactors=FALSE)
# Apply modifications as seen in the vignette (Chunk 6 and Chunk 14)
refGeneHg$Colors <- "red"
refGeneHg$Colors <- NULL

# Reproduce data-preparation code for ref_mm10
data_file4 <- system.file("extdata", "mm10_refGeneChr2-11-17-19.txt", package= "chromPlot")
ref_mm10   <- read.table(data_file4, sep="\t", stringsAsFactors=FALSE, header =TRUE)

# Reproduce data-preparation code for array
data_file5 <- system.file("extdata", "arrayChr17-19.txt", package = "chromPlot")
array      <- read.table(data_file5, sep="\t", header=TRUE, stringsAsFactors=FALSE)

# Reproduce data-preparation code for DEneg and DEpos
data_file6  <- system.file("extdata", "GenesDEChr17-19.bed", package = "chromPlot")
GenesDE     <- read.table(data_file6, sep="\t", header=TRUE, stringsAsFactors=FALSE)
DEpos       <- subset(GenesDE, nivel%in%"+")
DEneg       <- subset(GenesDE, nivel%in%"-")

# Reproduce data-preparation code for monocytes
data_file7 <- system.file("extdata", "monocitosDEChr19-21.txt", package = "chromPlot")
monocytes  <- read.table(data_file7, sep="\t", header=TRUE, stringsAsFactors=FALSE)

# Serialize objects to files in the working directory

# hg_gap: Data frame loaded via data(), save as RDS
saveRDS(hg_gap, "hg_gap")

# txgr: GRanges S4 object, save as RDS
saveRDS(txgr, "txgr")

# refGeneHg: Data frame originally read from a tab-separated file, save as tab-separated
write.table(refGeneHg, "refGeneHg", sep="\t", row.names=FALSE, quote=FALSE)

# ref_mm10: Data frame originally read from a tab-separated file, save as tab-separated
write.table(ref_mm10, "ref_mm10", sep="\t", row.names=FALSE, quote=FALSE)

# array: Data frame originally read from a tab-separated file, save as tab-separated
write.table(array, "array", sep="\t", row.names=FALSE, quote=FALSE)

# DEneg: Data frame subset from one originally read from a tab-separated file, save as tab-separated
write.table(DEneg, "DEneg", sep="\t", row.names=FALSE, quote=FALSE)

# DEpos: Data frame subset from one originally read from a tab-separated file, save as tab-separated
write.table(DEpos, "DEpos", sep="\t", row.names=FALSE, quote=FALSE)

# monocytes: Data frame originally read from a tab-separated file, save as tab-separated
write.table(monocytes, "monocytes", sep="\t", row.names=FALSE, quote=FALSE)