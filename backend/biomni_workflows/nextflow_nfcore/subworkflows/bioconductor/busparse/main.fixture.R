# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BUSpaRse", "TENxBUSData", "Matrix", "zeallot", "ggplot2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(BUSpaRse)
    library(TENxBUSData)
    library(Matrix)
    library(zeallot)
    library(ggplot2)
})

# Create the required directory for kallisto output files
dir.create("out_hgmm100", showWarnings = FALSE)

# 1. transcripts.txt
# Using the exact transcript IDs from the vignette's head(tr2g) output
# to ensure compatibility if the workflow queries them via transcript2gene()
transcripts <- c(
  "ENST00000434970.2",
  "ENST00000415118.1",
  "ENST00000448914.1",
  "ENST00000632684.1",
  "ENST00000390583.1",
  "ENST00000431440.2"
)
writeLines(transcripts, file.path("out_hgmm100", "transcripts.txt"))

# 2. matrix.ec
# Format: EC_ID \t transcript_indices (0-based, comma-separated)
matrix_ec <- c(
  "0\t0",
  "1\t1,2",
  "2\t3",
  "3\t4,5"
)
writeLines(matrix_ec, file.path("out_hgmm100", "matrix.ec"))

# 3. output.sorted.txt
# Format: Barcode \t UMI \t EC_ID \t Count
# Must be sorted by Barcode, then UMI, then EC_ID
bus_data <- c(
  "AAAAAAAACCCCCCCC\tAAAAAAAAAA\t0\t1",
  "AAAAAAAACCCCCCCC\tAAAAAAAAAA\t1\t2",
  "AAAAAAAACCCCCCCC\tCCCCCCCCCC\t2\t1",
  "GGGGGGGGTTTTTTTT\tGGGGGGGGGG\t3\t5"
)

# Write to the out_hgmm100 directory as expected by the vignette's make_sparse_matrix call
writeLines(bus_data, file.path("out_hgmm100", "output.sorted.txt"))

# Also write to the working directory as explicitly requested by the input spec
writeLines(bus_data, "output.sorted.txt")

# Verify files exist
stopifnot(
    file.exists("output.sorted.txt"),
    dir.exists("out_hgmm100"),
    file.exists(file.path("out_hgmm100", "output.sorted.txt")),
    file.exists(file.path("out_hgmm100", "matrix.ec")),
    file.exists(file.path("out_hgmm100", "transcripts.txt"))
)