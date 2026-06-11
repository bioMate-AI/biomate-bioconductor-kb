# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HPiP", "dplyr", "tibble", "stringr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(HPiP)
library(dplyr)
library(tibble)
library(stringr)

# Load the gold reference set from the package as shown in the vignette
data("Gold_ReferenceSet", package = "HPiP")

# The workflow expects intensity.csv and coldata.csv
# We construct synthetic files using the proteins from the Gold_ReferenceSet 
# to ensure compatibility if the workflow merges or filters based on these IDs.

proteins <- unique(c(Gold_ReferenceSet$Pathogen_Protein, Gold_ReferenceSet$Host_Protein))[1:50]

# Construct intensity.csv
intensity_data <- data.frame(
  Protein = proteins,
  Sample1 = runif(length(proteins), 10, 25),
  Sample2 = runif(length(proteins), 10, 25),
  Sample3 = runif(length(proteins), 10, 25),
  Sample4 = runif(length(proteins), 10, 25)
)
write.csv(intensity_data, "intensity.csv", row.names = FALSE)

# Construct coldata.csv
coldata_data <- data.frame(
  Sample = c("Sample1", "Sample2", "Sample3", "Sample4"),
  Condition = c("Control", "Control", "Infected", "Infected"),
  Replicate = c(1, 2, 1, 2)
)
write.csv(coldata_data, "coldata.csv", row.names = FALSE)