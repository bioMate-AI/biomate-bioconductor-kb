# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GenomicRanges)

# Construct synthetic GRanges object of gene annotations
genes <- GRanges(
    seqnames = rep("chr1", 5),
    ranges = IRanges(start = c(10000, 20000, 30000, 40000, 50000), width = 1000),
    strand = c("+", "-", "+", "-", "+"),
    gene_id = paste0("gene", 1:5)
)
names(genes) <- genes$gene_id

# Construct synthetic named numeric vector of gene expression values
rpkm <- c(gene1 = 12.5, gene2 = 0.5, gene3 = 45.2, gene4 = 8.0, gene5 = 100.1)

# Construct synthetic GRanges object of DNA methylation genomic scores
meth_starts <- seq(9000, 52000, by = 200)
meth <- GRanges(
    seqnames = "chr1",
    ranges = IRanges(start = meth_starts, width = 2),
    score = runif(length(meth_starts), min = 0, max = 1)
)

# Construct synthetic GRanges object of H3K4me3 ChIP-seq genomic scores
h3k4me3_starts <- seq(9000, 52000, by = 150)
H3K4me3 <- GRanges(
    seqnames = "chr1",
    ranges = IRanges(start = h3k4me3_starts, width = 50),
    score = rpois(length(h3k4me3_starts), lambda = 15)
)

# Serialize objects to the expected input files
saveRDS(genes, "genes.rds")
saveRDS(rpkm, "rpkm.rds")
saveRDS(meth, "meth.rds")
saveRDS(H3K4me3, "H3K4me3.rds")