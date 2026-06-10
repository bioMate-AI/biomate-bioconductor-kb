# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Gviz", "GenomicFeatures", "TxDb.Hsapiens.UCSC.hg19.knownGene")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Gviz)
library(GenomicFeatures)

# 1. Generate geneModels
# The vignette loads this from the package data. We serialize it to a file.
data(geneModels, package = "Gviz")
write.csv(geneModels, file = "geneModels.csv", row.names = FALSE)

# 2. Generate hg19_knownGene_sample.sqlite
# This is a standard sample TxDb file shipped with GenomicFeatures.
sqlite_path <- system.file("extdata", "hg19_knownGene_sample.sqlite", package = "GenomicFeatures")

if (file.exists(sqlite_path)) {
    file.copy(sqlite_path, "hg19_knownGene_sample.sqlite", overwrite = TRUE)
} else {
    # Fallback: create a TxDb database from the full annotation package if the sample is missing
    if (requireNamespace("TxDb.Hsapiens.UCSC.hg19.knownGene", quietly = TRUE)) {
        library(TxDb.Hsapiens.UCSC.hg19.knownGene)
        saveDb(TxDb.Hsapiens.UCSC.hg19.knownGene, file = "hg19_knownGene_sample.sqlite")
    }
}