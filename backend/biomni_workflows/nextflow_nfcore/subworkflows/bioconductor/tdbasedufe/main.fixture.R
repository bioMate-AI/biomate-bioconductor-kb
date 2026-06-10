# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TDbasedUFE", "tximport", "tximportData", "readr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TDbasedUFE)
library(tximport)
library(tximportData)
library(readr)

dir <- system.file("extdata", package="tximportData")
samples <- read.table(file.path(dir,"samples.txt"), header=TRUE)
samples$condition <- factor(rep(c("A","B"),each=3))
rownames(samples) <- samples$run

files <- file.path(dir,"salmon", samples$run, "quant.sf.gz")
names(files) <- samples$run
tx2gene <- read_csv(file.path(dir, "tx2gene.gencode.v27.csv"), show_col_types = FALSE)

txi <- tximport(files, type="salmon", tx2gene=tx2gene)

# Reduce features to 10,000 as in vignette
txi[seq_len(3)] <- lapply(txi[seq_len(3)], function(x) { x[seq_len(10000),] })

write.csv(txi$counts, "gene_expression_counts.csv", row.names = TRUE)
write.csv(samples, "sample_metadata.csv", row.names = TRUE)