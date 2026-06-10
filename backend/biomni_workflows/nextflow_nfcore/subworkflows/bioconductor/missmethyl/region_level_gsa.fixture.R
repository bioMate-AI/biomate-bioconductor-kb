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

# Read data from minfiData package
baseDir <- system.file("extdata", package = "minfiData")
targets <- read.metharray.sheet(baseDir)
rgSet <- read.metharray.exp(targets = targets)

# Preprocessing: SWAN normalization
mSet <- preprocessRaw(rgSet)
set.seed(123) # SWAN uses random sampling, set seed for reproducibility
mSetSw <- SWAN(mSet, verbose = TRUE)

# Filter out poor quality probes
detP <- detectionP(rgSet)
keep <- rowSums(detP < 0.01) == ncol(rgSet)
mSetSw <- mSetSw[keep,]

# Extract M-values and reduce computation time
set.seed(10) # Vignette's seed for sampling
mset_reduced <- mSetSw[sample(1:nrow(mSetSw), 20000),]
meth <- getMeth(mset_reduced)
unmeth <- getUnmeth(mset_reduced)
Mval <- log2((meth + 100)/(unmeth + 100))

# Create the design matrix
group <- factor(targets$status, levels = c("normal", "cancer"))
id <- factor(targets$person)
design <- model.matrix(~id + group)

# 2. Serialize objects to declared input files

# Save Mval as M.rds
saveRDS(Mval, "M.rds")

# Save design as design.rds
saveRDS(design, "design.rds")