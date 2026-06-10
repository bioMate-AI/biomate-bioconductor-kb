# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("subSeq", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(subSeq)
library(Biobase)

# Load the built-in hammer dataset
data(hammer)

# Prepare the count matrix and design as shown in the vignette
hammer.counts = Biobase::exprs(hammer)[, 1:4]
hammer.design = Biobase::pData(hammer)[1:4, ]
hammer.counts = hammer.counts[rowSums(hammer.counts) >= 5, ]

# Generate proportions for subsampling
proportions = 10^seq(-2, 0, .5)

# Run subsample to generate the subsamples object
subsamples = subsample(
    hammer.counts, 
    proportions, 
    method=c("edgeR", "voomLimma"), 
    treatment=hammer.design$protocol
)

# Retrieve the seed from the subsamples object
seed = getSeed(subsamples)

# Serialize the objects to the declared input files
# Since no specific read excerpt was provided, we use standard serialization
write.table(hammer.counts, file="hammer.counts", sep="\t", quote=FALSE, col.names=NA)
saveRDS(seed, file="seed.rds")