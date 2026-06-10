# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("annotate", "hgu95av2.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("annotate")

if (requireNamespace("hgu95av2.db", quietly = TRUE)) {
    library("hgu95av2.db")
    z <- buildChromLocation("hgu95av2")
}

# Create regions.bed
bed_data <- data.frame(
  chrom = c("chr1", "chr2", "chr3"),
  chromStart = c(100, 200, 300),
  chromEnd = c(150, 250, 350)
)
write.table(bed_data, file = "regions.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

# Create coldata.csv
coldata <- data.frame(
  sample = c("sample1", "sample2", "sample3"),
  condition = c("control", "treatment", "treatment")
)
write.csv(coldata, file = "coldata.csv", row.names = FALSE)