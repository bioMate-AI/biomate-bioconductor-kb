# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("methylclock", "methylclockData", "Biobase", "tibble")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(methylclock)
library(methylclockData)
library(Biobase)
library(tibble)

# Get TestDataset data as shown in the vignette
TestDataset <- get_TestDataset()

# Save MethylationData as an RDS file
saveRDS(TestDataset, "MethylationData")

# Extract sample names to create a matching covariates CSV
cnames <- colnames(TestDataset)
if (is.data.frame(TestDataset) && is.character(TestDataset[[1]])) {
    samples <- cnames[-1]
} else {
    samples <- cnames
}

# Create covariates data frame including chronological age
covariates <- data.frame(
    Sample = samples,
    Age = sample(20:60, length(samples), replace = TRUE),
    GestationalAge = sample(35:42, length(samples), replace = TRUE),
    stringsAsFactors = FALSE
)

# Save covariates as a CSV file
write.csv(covariates, file = "covariates", row.names = FALSE)