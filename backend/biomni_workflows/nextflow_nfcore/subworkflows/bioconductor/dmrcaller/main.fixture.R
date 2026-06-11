# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DMRcaller", "GenomicRanges", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DMRcaller)
library(GenomicRanges) # For GRanges, GRangesList
library(rtracklayer)   # For export.gff3

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the presaved methylation data list from the DMRcaller package
data(methylationDataList)

# 2. Serialize that object to EACH declared input file

# Write cond1.CX_report using the "WT" sample from methylationDataList
# The vignette explicitly uses saveBismark to create CX_report files.
saveBismark(methylationDataList[["WT"]], "cond1.CX_report")

# Write cond2.CX_report using the "met1-3" sample from methylationDataList
saveBismark(methylationDataList[["met1-3"]], "cond2.CX_report")

# Create and write genes.gff
# The vignette does not provide explicit code for genes.gff creation.
# However, it mentions "For a set of potential DMRs (e.g. genes, transposable elements or CpG islands)
# the user can call the function filterDMRs". This implies a GRanges-like input.
# We will create a plausible GRanges object representing genes on "Chr3",
# which is the chromosome covered by the example methylationDataList.
# The example data covers Chr3:101..999999.
genes_gr <- GRanges(
    seqnames = Rle("Chr3", 3),
    ranges = IRanges(
        start = c(10000, 50000, 150000),
        end = c(12000, 55000, 158000)
    ),
    strand = Rle(strand(c("+", "-", "+")), 1),
    type = "gene",
    source = "DMRcaller_fixture",
    score = NA,
    phase = NA,
    ID = c("gene1", "gene2", "gene3"),
    Name = c("GeneA", "GeneB", "GeneC")
)

# Export the GRanges object to a GFF3 file.
# rtracklayer::export.gff3 is the standard way to write GRanges to GFF.
export.gff3(genes_gr, "genes.gff")