# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BASiCS", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BASiCS)
library(SingleCellExperiment)

set.seed(1)
Counts <- matrix(rpois(50 * 40, 2), ncol = 40)
rownames(Counts) <- c(paste0("Gene", 1:40), paste0("Spike", 1:10))
colnames(Counts) <- paste0("Cell", 1:40)

set.seed(2)
SpikeInput <- rgamma(10, 1, 1)
SpikeInfo <- data.frame(
  "SpikeID" = paste0("Spike", 1:10),
  "SpikeInput" = SpikeInput
)

BatchInfo <- rep(c(1, 2), each = 20)

write.csv(Counts, "counts_matrix.csv", row.names = TRUE)
write.csv(SpikeInfo, "spike_info.csv", row.names = FALSE)
write.csv(data.frame(BatchInfo = BatchInfo), "batch_info.csv", row.names = FALSE)