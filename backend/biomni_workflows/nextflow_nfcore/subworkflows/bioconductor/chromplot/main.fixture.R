# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("chromPlot")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("chromPlot")

# Reproduce data preparation for hg_gap
# From vignette chunk 1:
data(hg_gap)

# Reproduce data preparation for hg_cytoBandIdeo
# From vignette chunk 4:
data(hg_cytoBandIdeo)

# Reproduce data preparation for refGeneHg
# From vignette chunk 6:
data_file1 <- system.file("extdata", "hg19_refGeneChr19-21.txt", package = "chromPlot")
refGeneHg <- read.table(data_file1, sep="\t", header=TRUE, stringsAsFactors=FALSE)
# The vignette later modifies refGeneHg (adds/removes Colors column).
# We save the initial state as read from the file, as this is what the workflow would "read".

# Reproduce data preparation for sinteny
# From vignette chunk 12:
data_file3 <- system.file("extdata", "sinteny_Hg-mm10Chr19-21.txt", package = "chromPlot")
sinteny <- read.table(data_file3, sep="\t", stringsAsFactors=FALSE, header=TRUE)

# Serialize objects to their respective input files in the working directory.
# Assuming tab-separated format based on how refGeneHg and sinteny are read in the vignette,
# and common practice for data frames loaded via data() that are expected as files.
write.table(hg_gap, "hg_gap", sep="\t", row.names=FALSE, quote=FALSE, col.names=TRUE)
write.table(hg_cytoBandIdeo, "hg_cytoBandIdeo", sep="\t", row.names=FALSE, quote=FALSE, col.names=TRUE)
write.table(refGeneHg, "refGeneHg", sep="\t", row.names=FALSE, quote=FALSE, col.names=TRUE)
write.table(sinteny, "sinteny", sep="\t", row.names=FALSE, quote=FALSE, col.names=TRUE)