# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PureCN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PureCN)

# Load the example PureCN output object shipped with the package
data(purecn.example.ret, package = "PureCN")

# Serialize the object to the required input file
saveRDS(purecn.example.ret, "Sample1_PureCN.rds")

# Create a synthetic BED file for callable regions
callable_bed <- data.frame(
    chrom = c("chr1", "chr2", "chr3"),
    chromStart = c(10000, 20000, 30000),
    chromEnd = c(15000, 25000, 35000),
    name = rep("CALLABLE", 3)
)

write.table(callable_bed, "callable_status.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)