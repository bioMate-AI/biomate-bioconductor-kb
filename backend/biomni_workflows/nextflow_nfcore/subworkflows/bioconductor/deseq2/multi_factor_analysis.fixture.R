# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DESeq2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DESeq2)

# Generate a synthetic DESeqDataSet using the package's built-in generator
dds <- makeExampleDESeqDataSet(n = 1000, m = 12)

# Adjust colData to match the vignette's expected variables and levels
# The vignette uses: design= ~ batch + condition
# and tests for: name="condition_trt_vs_untrt"
dds$batch <- factor(rep(c("batch1", "batch2"), times = 6))
dds$condition <- factor(rep(c("untrt", "trt"), each = 6))
design(dds) <- ~ batch + condition

# Serialize the S4 object to the expected input file
saveRDS(dds, "dds.rds")