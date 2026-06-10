# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DiscoRhythm")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DiscoRhythm)

# Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette section 6.1 "Importing Data" uses this:
data(cycSimu4h2d)

# The workflow reads `temporal_data.csv` with `read.csv(input_file, header = TRUE, check.names = FALSE)`.
# Section 4.1 "Example Dataset" shows the first column explicitly named "IDs".
# `cycSimu4h2d` is a data frame where row names are the feature IDs.
# Convert row names to a column named "IDs" before writing to CSV.
output_df <- data.frame(IDs = rownames(cycSimu4h2d), cycSimu4h2d, check.names = FALSE)

# Serialize the object to the declared input file in the exact format
write.csv(output_df, "temporal_data.csv", row.names = FALSE)