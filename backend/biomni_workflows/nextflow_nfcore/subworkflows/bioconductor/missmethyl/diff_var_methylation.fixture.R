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

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Reading data into R
baseDir <- system.file("extdata", package = "minfiData")
targets <- read.metharray.sheet(baseDir)
rgSet <- read.metharray.exp(targets = targets)

# Subset-quantile within array normalization (SWAN)
# Note: The vignette uses preprocessRaw(rgSet) before SWAN,
# but SWAN can take RGChannelSet directly. Sticking to vignette's exact steps.
mSet <- preprocessRaw(rgSet)
set.seed(123) # Add set.seed for SWAN reproducibility as recommended by vignette
mSetSw <- SWAN(mSet, verbose = FALSE) # Set verbose to FALSE for non-interactive script

# Filter out poor quality probes
detP <- detectionP(rgSet)
keep <- rowSums(detP < 0.01) == ncol(rgSet)
mSetSw <- mSetSw[keep,]

# Extracting M-values
set.seed(10) # Important for reproducibility of the sample
mset_reduced <- mSetSw[sample(1:nrow(mSetSw), 20000),]
meth <- getMeth(mset_reduced)
unmeth <- getUnmeth(mset_reduced)
Mval <- log2((meth + 100)/(unmeth + 100))

# Setting up the design matrix
group <- factor(targets$status,levels=c("normal","cancer"))
id <- factor(targets$person)
design <- model.matrix(~id + group)

# 2. Serialize the objects to EACH declared input file in the EXACT format

# Save Mval as Mval.rds
saveRDS(Mval, "Mval.rds")

# Save design as design.rds
saveRDS(design, "design.rds")