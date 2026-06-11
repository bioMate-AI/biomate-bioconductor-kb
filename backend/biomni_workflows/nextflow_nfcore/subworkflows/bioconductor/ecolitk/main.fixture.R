# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ecolitk", "Biobase", "ecoliLeucine")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ecolitk)
library(Biobase)
library(ecoliLeucine)

# 1. Generate coldata.csv
data(ecoliLeucine)
coldata <- pData(ecoliLeucine)

# Fallback in case pData is empty
if (is.null(coldata) || nrow(coldata) == 0) {
    coldata <- data.frame(
        sample = c("sample1", "sample2", "sample3", "sample4"),
        strain = c("lrp+", "lrp+", "lrp-", "lrp-"),
        row.names = c("sample1", "sample2", "sample3", "sample4")
    )
}
write.csv(coldata, "coldata.csv", row.names = TRUE)

# 2. Generate regions.bed
data(ecoligenomeCHRLOC)
data(ecoligenomeBNUM)
data(ecoligenomeBNUM2STRAND)

affyids <- ls(ecoligenomeCHRLOC)
affypos <- mget(affyids, ecoligenomeCHRLOC, ifnotfound = NA)
beg.end <- matrix(unlist(affypos), nc = 2, byrow = TRUE)

bnums <- unlist(mget(affyids, ecoligenomeBNUM, ifnotfound = NA))
strands <- unlist(mget(bnums, ecoligenomeBNUM2STRAND, ifnotfound = NA))

# Convert strands to BED format (+, -, *)
strands_bed <- ifelse(strands == ">", "+", ifelse(strands == "<", "-", "*"))
strands_bed[is.na(strands_bed)] <- "*"

bed <- data.frame(
  chrom = "Ecoli",
  chromStart = beg.end[, 1],
  chromEnd = beg.end[, 2],
  name = affyids,
  score = 0,
  strand = strands_bed
)

# Remove any rows with missing coordinates
bed <- bed[!is.na(bed$chromStart) & !is.na(bed$chromEnd), ]

write.table(bed, "regions.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)