# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GenomicRanges", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GenomicRanges)
library(rtracklayer)

# Create synthetic peaks to avoid out-of-bounds errors during normalizeToMatrix (extend = 5000)
peak1_gr <- GRanges(
    seqnames = "chr6", 
    ranges = IRanges(start = c(10000, 20000, 30000), width = 500), 
    score = c(10, 20, 30)
)
peak2_gr <- GRanges(
    seqnames = "chr6", 
    ranges = IRanges(start = c(10000, 25000, 30000), width = 500), 
    score = c(15, 25, 35)
)

# Export to the filenames used in the vignette
export(peak1_gr, "Rep1_peaks_ucsc_chr6.bed", format = "bed")
export(peak2_gr, "Rep2_peaks_ucsc_chr6.bed", format = "bed")

# Create synthetic reads
set.seed(123)
read1_gr <- GRanges(
    seqnames = "chr6", 
    ranges = IRanges(start = sample(5000:35000, 1000, replace = TRUE), width = 50)
)
read2_gr <- GRanges(
    seqnames = "chr6", 
    ranges = IRanges(start = sample(5000:35000, 1000, replace = TRUE), width = 50)
)
input_gr <- GRanges(
    seqnames = "chr6", 
    ranges = IRanges(start = sample(5000:35000, 1000, replace = TRUE), width = 50)
)

# Export to the filenames used in the vignette
export(read1_gr, "H3K27ac_rep1_filtered_ucsc_chr6.bed", format = "bed")
export(read2_gr, "H3K27ac_rep2_filtered_ucsc_chr6.bed", format = "bed")
export(input_gr, "ES_input_filtered_ucsc_chr6.bed", format = "bed")

# Also write to literal names just in case the workflow expects them directly
export(peak1_gr, "path_peaks", format = "bed")
export(read1_gr, "path_reads", format = "bed")