# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dmrseq", "bsseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dmrseq)
library(bsseq)

# Load the example dataset provided by the dmrseq package
data(BS.chr21, package = "dmrseq")
bs <- BS.chr21

# Subset to a smaller number of loci to ensure the test fixture is lightweight
bs <- bs[1:2000, ]

# Extract or assign sample names as per the vignette
sample_names <- sampleNames(bs)
if (is.null(sample_names)) {
    sample_names <- c("imr90.r1", "imr90.r2", "h1.r1", "h1.r2")
    sampleNames(bs) <- sample_names
}

# Define the condition covariates
celltype <- c("imr90", "imr90", "h1", "h1")

# Add metadata to the BSseq object
pData(bs)$CellType <- celltype
pData(bs)$Replicate <- substr(sample_names, nchar(sample_names), nchar(sample_names))

# Save the pre-constructed BSseq object
saveRDS(bs, "bs_object.rds")

# Create and save the sample metadata CSV
metadata <- data.frame(
  sampleName = sample_names,
  CellType = celltype,
  Replicate = pData(bs)$Replicate,
  stringsAsFactors = FALSE
)
write.csv(metadata, "sample_metadata.csv", row.names = FALSE)