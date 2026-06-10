# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cogena")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cogena)

# Load the example dataset provided by the package
data(Psoriasis)

# Serialize the R objects to the working directory as RDS files
saveRDS(DEexprs, "DEexprs.csv")
saveRDS(sampleLabel, "sampleLabel.txt")

# Locate a GMT gene set file shipped with the package and copy it to 'annofile'
gmt_files <- list.files(system.file("extdata", package="cogena"), pattern="\\.gmt", full.names=TRUE)

if (length(gmt_files) > 0) {
    file.copy(gmt_files[1], "annofile.gmt", overwrite = TRUE)
} else {
    # Fallback: create a minimal synthetic GMT file if none are found
    writeLines(c("PATHWAY_A\t\tGene1\tGene2", "PATHWAY_B\t\tGene3\tGene4"), "annofile")
}