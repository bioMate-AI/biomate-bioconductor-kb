# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("seqPattern", "BSgenome.Drerio.UCSC.danRer7")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(seqPattern)
library(BSgenome.Drerio.UCSC.danRer7)

# Reproduce the vignette's data preparation for zebrafishPromoters24h
data(zebrafishPromoters24h)

# Serialize zebrafishPromoters24h to coordinates.txt
# The workflow reads with: read.table("coordinates.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
write.table(zebrafishPromoters24h, file = "coordinates.txt", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Serialize the genome package name to genome_assembly
# The workflow reads with: genome_package <- readLines("genome_assembly", n = 1, warn = FALSE)
cat("BSgenome.Drerio.UCSC.danRer7", file = "genome_assembly")