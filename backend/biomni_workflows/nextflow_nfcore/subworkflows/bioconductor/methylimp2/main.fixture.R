# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("methyLImp2", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(methyLImp2)
library(SummarizedExperiment)

# Load the dataset
data(beta, package = "methyLImp2")

# Generate artificial NAs
with_missing_data <- generateMissingData(beta, lambda = 3.5)
beta_with_nas <- with_missing_data$beta_with_nas

# Construct SummarizedExperiment
data(beta_meta, package = "methyLImp2")
beta_SE <- SummarizedExperiment(
    assays = SimpleList(beta = t(beta_with_nas)), 
    colData = beta_meta
)

# Serialize the object to the expected input file
saveRDS(beta_SE, "beta_SE.rds")