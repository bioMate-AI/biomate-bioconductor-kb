# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("KEGGREST")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(KEGGREST)

bed <- data.frame(
    chrom = c("chr1", "chr2", "chr3"),
    chromStart = c(10000, 20000, 30000),
    chromEnd = c(10500, 20500, 30500),
    name = c("region1", "region2", "region3"),
    score = c(10, 20, 30),
    strand = c("+", "-", "+")
)
write.table(bed, file = "regions.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

coldata <- data.frame(
    sample_id = c("Sample1", "Sample2", "Sample3", "Sample4"),
    condition = c("Control", "Control", "Treated", "Treated"),
    replicate = c(1, 2, 1, 2)
)
write.csv(coldata, file = "coldata.csv", row.names = FALSE, quote = FALSE)