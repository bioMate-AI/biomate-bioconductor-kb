# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("metaMS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(metaMS)

# Load example data from the package
data(LCresults)

# Extract the peak table to serve as the intensity matrix
intensity_data <- LCresults$PeakTable

# Write intensity.csv
write.csv(intensity_data, file = "intensity.csv", row.names = TRUE)

# Create a corresponding coldata.csv
# We use the column names of the intensity data as sample names
sample_names <- colnames(intensity_data)
coldata <- data.frame(
    Sample = sample_names,
    Condition = rep(c("Control", "Treatment"), length.out = length(sample_names))
)

# Write coldata.csv
write.csv(coldata, file = "coldata.csv", row.names = FALSE)