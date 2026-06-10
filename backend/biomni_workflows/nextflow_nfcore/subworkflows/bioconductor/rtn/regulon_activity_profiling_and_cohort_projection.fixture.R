# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RTN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RTN)

# Load the dataset provided by the RTN package
data(tniData)

# 1. Prepare the TNI object for Cohort A
tfs <- c("FOXM1", "E2F2", "E2F3", "RUNX2", "PTTG1")
rtni <- tni.constructor(expData = tniData$expData, 
                        regulatoryElements = tfs, 
                        rowAnnotation = tniData$rowAnnotation, 
                        colAnnotation = tniData$colAnnotation)

# Run the TNI pipeline steps (using a small number of permutations for speed in testing)
rtni <- tni.permutation(rtni, nPermutations = 10)
rtni <- tni.bootstrap(rtni)
rtni <- tni.dpi.filter(rtni)

# Save the calculated TNI object to the expected RData file
save(rtni, file = "cohort_a_tni.RData")

# 2. Prepare the gene expression matrix for Cohort B
# Using the same example expression data to represent Cohort B's expression matrix
write.csv(tniData$expData, file = "cohort_b_expression.csv", row.names = TRUE)