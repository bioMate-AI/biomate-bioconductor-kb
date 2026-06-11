# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVrd2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library('CNVrd2')

# Load data into R. This loads 'objectCNVrd2' and 'resultSegment' into the environment
# from the fcgr3bMXL dataset, which is part of the CNVrd2 package.
data(fcgr3bMXL)

# Extract the standardized count matrix from the loaded resultSegment.
# This matrix is used in the subsequent segmentation step.
readCountMatrix <- resultSegment$stdCntMatrix

# Create a new CNVrd2 object. This step re-initializes 'objectCNVrd2'
# with specific parameters as shown in the vignette.
objectCNVrd2 <- new("CNVrd2", windows = 1000, chr = "chr1",
                    st = 161100001, en = 162100000,
                    dirBamFile = "BamMXL",
                    genes = c(161592986, 161601753),
                    geneNames = "3B")

# Obtain segmentation scores by calling segmentSamples.
# This re-computes 'resultSegment' using the newly created 'objectCNVrd2'
# and the 'readCountMatrix' obtained from the initial data load.
resultSegment <- segmentSamples(Object = objectCNVrd2, stdCntMatrix = readCountMatrix)

# Serialize the final 'objectCNVrd2' and 'resultSegment' objects
# to files in the working directory, using saveRDS for R objects.
saveRDS(objectCNVrd2, file = "objectCNVrd2")
saveRDS(resultSegment, file = "resultSegment")