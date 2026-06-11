# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Cogito", "TxDb.Mmusculus.UCSC.mm9.knownGene")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Cogito)
library(TxDb.Mmusculus.UCSC.mm9.knownGene)

# Load the example datasets provided by the Cogito package
data("MurEpi.RNA.small", package = "Cogito")
data("MurEpi.RRBS.small", package = "Cogito")
data("MurEpi.ChIP.small", package = "Cogito")

# Create the ranges list as done in the vignette
example.dataset <- list(
    ChIP = MurEpi.ChIP.small, 
    RNA = MurEpi.RNA.small, 
    RRBS = MurEpi.RRBS.small
)

# Serialize the ranges object to the expected input file
saveRDS(example.dataset, "ranges.rds")

# Get the organism TxDb object as done in the vignette
mm9 <- TxDb.Mmusculus.UCSC.mm9.knownGene::TxDb.Mmusculus.UCSC.mm9.knownGene

# Serialize the organism object to the expected input file
saveRDS(mm9, "organism.rds")