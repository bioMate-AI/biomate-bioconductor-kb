# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("missMethyl", "limma", "minfi", "minfiData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(missMethyl)
library(limma)
library(minfi)
library(minfiData)

# Set seed for reproducibility of SWAN and sample()
set.seed(10)

# 2 Reading data into R
baseDir <- system.file("extdata", package = "minfiData")
targets <- read.metharray.sheet(baseDir)
rgSet <- read.metharray.exp(targets = targets)

# 3 Subset-quantile within array normalization (SWAN)
mSet <- preprocessRaw(rgSet)
mSetSw <- SWAN(mSet, verbose = TRUE)

# 4 Filter out poor quality probes
detP <- detectionP(rgSet)
keep <- rowSums(detP < 0.01) == ncol(rgSet)
mSetSw <- mSetSw[keep,]

# 5 Extracting beta and M-values
# The set.seed(10) call is placed at the top for overall reproducibility
mset_reduced <- mSetSw[sample(1:nrow(mSetSw), 20000),]
meth <- getMeth(mset_reduced)
unmeth <- getUnmeth(mset_reduced)
Mval <- log2((meth + 100)/(unmeth + 100))
beta <- getBeta(mset_reduced)

# Prepare objects for output files as per workflow requirements:
# counts: The M-value matrix (Mval)
# annot: The sample annotation data frame (targets)
# gender: The gender covariate vector (targets$sex)

# Serialize objects to the specified input files using saveRDS,
# which is robustly handled by the workflow's read functions.
saveRDS(Mval, "counts")
saveRDS(targets, "annot")
saveRDS(targets$sex, "gender")