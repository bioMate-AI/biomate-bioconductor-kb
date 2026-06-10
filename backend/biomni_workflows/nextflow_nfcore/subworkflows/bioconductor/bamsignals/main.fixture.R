# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bamsignals", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bamsignals)
library(GenomicRanges)

# Load the example annotation from the bamsignals package
genes <- get(load(system.file("extdata", "randomAnnot.Rdata", package="bamsignals")))

# Serialize the GRanges object to a BED file (0-based start, 1-based end)
bed_df <- data.frame(
    chrom = as.character(seqnames(genes)),
    start = start(genes) - 1,
    end = end(genes),
    name = paste0("region_", seq_along(genes)),
    score = 0,
    strand = as.character(strand(genes))
)
write.table(bed_df, "regions.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)

# Create a coldata.csv referencing the example BAM file shipped with the package
bampath <- system.file("extdata", "randomBam.bam", package="bamsignals")
coldata <- data.frame(
    sample = "randomBam",
    bam_file = bampath,
    condition = "control",
    stringsAsFactors = FALSE
)
write.csv(coldata, "coldata.csv", row.names=FALSE)