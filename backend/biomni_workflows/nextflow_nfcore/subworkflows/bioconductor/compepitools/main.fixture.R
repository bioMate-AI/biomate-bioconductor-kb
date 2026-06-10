# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("compEpiTools", "Rsamtools")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(compEpiTools)
library(Rsamtools)

# 1. Reproduce the vignette's data-preparation code to materialize the example object 'gr'.
# This code block is taken directly from the "GRcounting" section of the compEpiTools vignette.
ir <- IRanges(start=c(1000, 100), end=c(2000, 1000))
gr <- GRanges(seqnames=Rle(c('seq1','seq2')), ranges=ir)

# 2. Serialize the 'gr' object to the input file 'user_regions.RData'.
# The workflow expects to load an R object from this file.
save(gr, file="user_regions.RData")

# 3. Prepare the 'aligned_reads.bam' input file.
# The vignette uses 'ex1.bam' from the Rsamtools package as its example BAM file.
# We copy this file to the expected input filename.
vignette_bampath <- system.file("extdata", "ex1.bam", package="Rsamtools")
output_bampath <- "aligned_reads.bam"

# Copy the example BAM file. 'overwrite = TRUE' ensures it works if run multiple times.
file.copy(from = vignette_bampath, to = output_bampath, overwrite = TRUE)