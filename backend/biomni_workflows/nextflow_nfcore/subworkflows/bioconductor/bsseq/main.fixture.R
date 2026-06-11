# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bsseq", "bsseqData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bsseq)
library(bsseqData)

# Load the example dataset from the companion package as shown in the vignette
data(BS.cancer.ex)
BS.cancer.ex <- updateObject(BS.cancer.ex)

# Subset to a smaller number of loci for a lightweight test fixture
BS.cancer.ex <- BS.cancer.ex[1:1000, ]

# Extract genomic positions
gr <- granges(BS.cancer.ex)
alignment_summaries <- data.frame(
    chr = as.character(seqnames(gr)),
    pos = start(gr),
    stringsAsFactors = FALSE
)

# Extract Methylation (M) and Coverage (Cov) values
M_vals <- getCoverage(BS.cancer.ex, type = "M")
Cov_vals <- getCoverage(BS.cancer.ex, type = "Cov")

# Combine into the summarized evidence data frame
for (sample_name in sampleNames(BS.cancer.ex)) {
    alignment_summaries[[paste0(sample_name, "_M")]] <- as.vector(M_vals[, sample_name])
    alignment_summaries[[paste0(sample_name, "_Cov")]] <- as.vector(Cov_vals[, sample_name])
}

# Write the raw alignment summaries to a text file
write.table(
    alignment_summaries, 
    file = "raw_alignment_summaries.txt", 
    sep = "\t", 
    row.names = FALSE, 
    quote = FALSE
)

# Extract sample phenotypes and group assignments
sample_metadata <- as.data.frame(pData(BS.cancer.ex))

# Write the sample metadata to a CSV file
write.csv(
    sample_metadata, 
    file = "sample_metadata.csv", 
    row.names = TRUE
)