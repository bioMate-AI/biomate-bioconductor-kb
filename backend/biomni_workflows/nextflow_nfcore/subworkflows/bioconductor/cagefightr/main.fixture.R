# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CAGEfightR", "TxDb.Mmusculus.UCSC.mm9.knownGene", "AnnotationDbi")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CAGEfightR)
library(TxDb.Mmusculus.UCSC.mm9.knownGene)
library(AnnotationDbi)

# Load the example design matrix from CAGEfightR
data("exampleDesign", package = "CAGEfightR")

# The workflow expects exactly 'plus_strand.bw' and 'minus_strand.bw'.
# We will use the first sample from the example data to create these files.
sample_idx <- 1

bw_plus_src <- system.file("extdata", exampleDesign$BigWigPlus[sample_idx], package = "CAGEfightR")
bw_minus_src <- system.file("extdata", exampleDesign$BigWigMinus[sample_idx], package = "CAGEfightR")

# Copy the BigWig files to the working directory with the expected names
file.copy(bw_plus_src, "plus_strand.bw", overwrite = TRUE)
file.copy(bw_minus_src, "minus_strand.bw", overwrite = TRUE)

# Create the design matrix CSV pointing to the newly named BigWig files
design_df <- exampleDesign[sample_idx, , drop = FALSE]
design_df$BigWigPlus <- "plus_strand.bw"
design_df$BigWigMinus <- "minus_strand.bw"
write.csv(design_df, "design_matrix.csv", row.names = FALSE)

# Save the TxDb annotation object to the expected file
txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene
saveDb(txdb, file = "txdb_annotation")