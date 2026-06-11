# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("genomeIntervals")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(genomeIntervals)
data("gen_ints")

bed_data <- data.frame(
  chrom = as.character(seqnames(i)),
  start = as.integer(i[,1]) - 1,
  end = as.integer(i[,2]),
  name = rownames(i),
  score = 0,
  strand = as.character(strand(i))
)
write.table(bed_data, file = "regions.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

coldata <- data.frame(
  sample = c("sample1", "sample2"),
  condition = c("control", "treatment")
)
write.csv(coldata, file = "coldata.csv", row.names = FALSE)