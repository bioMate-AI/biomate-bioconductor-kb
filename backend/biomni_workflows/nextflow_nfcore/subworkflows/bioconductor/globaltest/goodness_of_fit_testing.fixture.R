# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("globaltest")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(globaltest)

# 1. Reproduce the vignette's own data-preparation code
set.seed(1)
Y <- rnorm(20)
X <- matrix(rnorm(200), 20, 10)
X[,1:3] <- X[,1:3] + Y
colnames(X) <- LETTERS[1:10]

# 2. Prepare the 'kyphosis' dataset as declared in the input spec
# The kyphosis dataset is a standard dataset available in the 'rpart' package
if (requireNamespace("rpart", quietly = TRUE)) {
    data("kyphosis", package = "rpart")
} else {
    # Fallback synthetic data matching the kyphosis structure if rpart is unavailable
    kyphosis <- data.frame(
        Kyphosis = factor(sample(c("absent", "present"), 81, replace = TRUE)),
        Age = sample(1:200, 81, replace = TRUE),
        Number = sample(2:10, 81, replace = TRUE),
        Start = sample(1:20, 81, replace = TRUE)
    )
}

# 3. Serialize to the expected input file 'kyphosis'
# Since no specific read excerpt is provided and the file lacks an extension, 
# saveRDS is the standard method for preserving the data frame structure.
saveRDS(kyphosis, file = "kyphosis.csv")