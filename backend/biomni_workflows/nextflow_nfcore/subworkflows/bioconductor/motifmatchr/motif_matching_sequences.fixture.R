# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("motifmatchr", "GenomicRanges", "Biostrings", "BSgenome.Hsapiens.UCSC.hg19")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(motifmatchr)
library(GenomicRanges)
library(Biostrings)
library(BSgenome.Hsapiens.UCSC.hg19)

# Load example motifs
data(example_motifs, package = "motifmatchr")

# Make a set of peaks as described in the vignette
peaks <- GRanges(
    seqnames = c("chr1", "chr2", "chr2"),
    ranges = IRanges(
        start = c(76585873, 42772928, 100183786),
        width = 500
    )
)

# Generate DNAStringSet using the peaks and BSgenome
example_DNAStringSet <- getSeq(BSgenome.Hsapiens.UCSC.hg19, peaks)

# Generate character vector from the DNAStringSet
example_character <- as.character(example_DNAStringSet)

# Serialize the objects to the working directory as requested
saveRDS(example_DNAStringSet, "example_DNAStringSet")
saveRDS(example_character, "example_character")
saveRDS(example_motifs, "example_motifs")