# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVrd2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNVrd2)

# 1. Reproduce the vignette's data-preparation code for ccl3l1data
data(ccl3l1data)

# 2. Serialize ccl3l1data to a file named 'ccl3l1data' in the working directory
# Using write.table with tab separator and no quotes, consistent with common data frame serialization
# and the vignette's later use of write.table.
write.table(ccl3l1data, "ccl3l1data.csv", sep = "\t", quote = FALSE, row.names = FALSE)

# 3. Obtain the path to the chr17.34800000.34830000.vcf.gz file from the package's extdata
vcfFileCCL3L1_source <- system.file(package = "CNVrd2", "extdata", "chr17.34800000.34830000.vcf.gz")

# 4. Copy the VCF file to the working directory, as the workflow reads it from there
file.copy(vcfFileCCL3L1_source, "chr17.34800000.34830000.vcf.gz")