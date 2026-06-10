# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MSstatsConvert")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MSstatsConvert)

# Reproduce the vignette's data-preparation code to materialize the example object.
# The workflow reads "openmstmt_input.csv". The vignette shows how to get this data
# from within the MSstatsConvert package itself.
openms_input_data <- read.csv(system.file("tinytest/raw_data/OpenMSTMT/openmstmt_input.csv", package = "MSstatsConvert"))

# Serialize the object to the declared input file in the exact format the workflow reads.
# The workflow uses read.csv("openmstmt_input.csv"), so we write a CSV file.
# Ensure row names are not written, as read.csv would interpret them as an extra column.
write.csv(openms_input_data, "openmstmt_input.csv", row.names = FALSE)