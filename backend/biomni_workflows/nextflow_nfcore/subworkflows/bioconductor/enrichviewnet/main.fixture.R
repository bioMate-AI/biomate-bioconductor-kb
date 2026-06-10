# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("enrichViewNet", "gprofiler2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(enrichViewNet)
library(gprofiler2)

# Load datasets from the vignette
data("parentalNapaVsDMSODEG", package = "enrichViewNet")
data("parentalNapaVsDMSOEnrichment", package = "enrichViewNet")

# The workflow expects intensity.csv and coldata.csv
# We serialize the vignette's DEG data to intensity.csv as a proxy
write.csv(parentalNapaVsDMSODEG, "intensity.csv", row.names = FALSE)

# Create a synthetic coldata.csv
coldata <- data.frame(
    Sample = c("Sample1", "Sample2"),
    Condition = c("Control", "Treated")
)
write.csv(coldata, "coldata.csv", row.names = FALSE)