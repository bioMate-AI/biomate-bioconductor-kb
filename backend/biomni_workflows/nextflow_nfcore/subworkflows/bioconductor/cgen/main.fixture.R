# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CGEN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CGEN)

# Get the paths to the sample data files included in the CGEN package
geno_data_src <- system.file("sampleData", "geno_data.tped.gz", package="CGEN")
tfam_data_src <- system.file("sampleData", "geno_data.tfam", package="CGEN")
pheno_data_src <- system.file("sampleData", "pheno.txt", package="CGEN")

# Copy the sample data files to the current working directory
# These files will serve as the input for the workflow
file.copy(geno_data_src, "geno_data.tped.gz", overwrite = TRUE)
file.copy(tfam_data_src, "geno_data.tfam", overwrite = TRUE)
file.copy(pheno_data_src, "pheno.txt", overwrite = TRUE)