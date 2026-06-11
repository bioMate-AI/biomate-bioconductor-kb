# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("epivizrChart")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(epivizrChart)

# Load datasets used in the vignette
data(tcga_colon_blocks)
data(tcga_colon_curves)
data(tcga_colon_expression)
data(apColonData)

# Create the required input.csv file with generic genomic data
# as the specific read excerpt was empty but the file is required.
df <- data.frame(
  chr = c("chr11", "chr11", "chr11"),
  start = c(118000000, 119000000, 120000000),
  end = c(118500000, 119500000, 120500000),
  value = c(1.5, 2.0, 0.8)
)

write.csv(df, "input.csv", row.names = FALSE)