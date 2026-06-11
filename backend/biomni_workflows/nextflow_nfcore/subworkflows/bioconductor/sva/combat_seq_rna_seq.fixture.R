# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("sva")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(sva)

# Reproduce the simulated RNA-Seq count data and metadata from the vignette
set.seed(123)
count_matrix <- matrix(rnbinom(400, size=10, prob=0.1), 
                       nrow=50, ncol=8)

# Add row and column names for the CSV output
rownames(count_matrix) <- paste0("gene", 1:50)
colnames(count_matrix) <- paste0("sample", 1:8)

# Reproduce the batch, group, and covariate variables from the vignette
batch <- c(rep(1, 4), rep(2, 4))
group <- rep(c(0,1), 4)
cov1 <- rep(c(0,1), 4)
cov2 <- c(0,0,1,1,0,0,1,1)

sample_metadata <- data.frame(
    sample = colnames(count_matrix),
    batch = batch,
    group = group,
    cov1 = cov1,
    cov2 = cov2
)

# Serialize to the required input files
write.csv(count_matrix, "raw_counts.csv", row.names = TRUE, quote = FALSE)
write.csv(sample_metadata, "sample_metadata.csv", row.names = FALSE, quote = FALSE)