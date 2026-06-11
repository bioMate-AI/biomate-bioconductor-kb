# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("biomformat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(biomformat)

rich_sparse_file <- system.file("extdata", "rich_sparse_otu_table.biom", package = "biomformat")
x4 <- read_biom(rich_sparse_file)

abundance <- as(biom_data(x4), "matrix")
write.csv(abundance, "abundance.csv", row.names = TRUE)

coldata <- sample_metadata(x4)
write.csv(coldata, "coldata.csv", row.names = TRUE)