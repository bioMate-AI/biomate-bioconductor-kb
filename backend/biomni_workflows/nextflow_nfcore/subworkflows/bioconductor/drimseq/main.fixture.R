# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DRIMSeq", "PasillaTranscriptExpr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DRIMSeq) # As requested, though not strictly needed for file generation
library(PasillaTranscriptExpr)

# Get the directory where the example data is stored within the package
data_dir <- system.file("extdata", package = "PasillaTranscriptExpr")

# Load the metadata table as it is done in the vignette
pasilla_metadata <- read.table(file.path(data_dir, "metadata.txt"),
  header = TRUE, as.is = TRUE)

# Load the counts table as it is done in the vignette
pasilla_counts <- read.table(file.path(data_dir, "counts.txt"),
  header = TRUE, as.is = TRUE)

# Load the gene_id_subset as it is done in the vignette
gene_id_subset <- readLines(file.path(data_dir, "gene_id_subset.txt"))

# Write the pasilla_metadata object to "metadata.txt"
# Use tab separator, no row names, and no quotes to match read.table(..., as.is=TRUE)
write.table(pasilla_metadata, "metadata.txt",
  sep = "\t", row.names = FALSE, quote = FALSE)

# Write the pasilla_counts object to "pasilla_counts.txt"
# Use tab separator, no row names, and no quotes to match read.table(..., as.is=TRUE)
write.table(pasilla_counts, "pasilla_counts.txt",
  sep = "\t", row.names = FALSE, quote = FALSE)

# Write the gene_id_subset vector to "gene_id_subset.txt"
writeLines(gene_id_subset, "gene_id_subset.txt")