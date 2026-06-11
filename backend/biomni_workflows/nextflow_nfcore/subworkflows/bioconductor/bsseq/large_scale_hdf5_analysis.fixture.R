# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bsseq", "bsseqData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bsseq)
library(bsseqData)

data(BS.cancer.ex)
BS.cancer.ex <- updateObject(BS.cancer.ex)

gr <- granges(BS.cancer.ex)
meth <- getCoverage(BS.cancer.ex, type = "M")[, 1]
cov <- getCoverage(BS.cancer.ex, type = "Cov")[, 1]

keep <- cov > 0
gr <- gr[keep]
meth <- meth[keep]
cov <- cov[keep]
unmeth <- cov - meth
meth_perc <- (meth / cov) * 100

cov_df <- data.frame(
    chr = as.character(seqnames(gr)),
    start = start(gr),
    end = end(gr),
    meth_perc = round(meth_perc, 6),
    meth = meth,
    unmeth = unmeth
)

write.table(cov_df, file = "bismark_files.cov", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)