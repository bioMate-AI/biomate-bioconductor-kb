# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SummarizedExperiment", "S4Vectors")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SummarizedExperiment)
library(S4Vectors)

# Create sampleTable
sampleTable <- DataFrame(
    Sample = paste0("Sample", 1:12),
    Disease = rep(c("Autism", "Control"), each = 6),
    Region = rep(c("Cbl", "Ctx", "Hippo"), times = 4)
)

# Create autism_se
set.seed(123)
mat <- matrix(rnorm(1200, mean = 5, sd = 2), ncol = 12)
colnames(mat) <- sampleTable$Sample
rownames(mat) <- paste0("Gene", 1:100)

autism_se <- SummarizedExperiment(
    assays = list(exprs = mat),
    colData = sampleTable
)

# Serialize to the declared input files
saveRDS(autism_se, "autism_se.rds")
saveRDS(sampleTable, "sampleTable.rds")