# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("gg4way", "airway", "org.Hs.eg.db", "DESeq2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("gg4way")
library("airway")
library("org.Hs.eg.db")
library("DESeq2")

data("airway")
se <- airway

rowData(se)$symbol <- mapIds(org.Hs.eg.db,
                             keys = rownames(se),
                             column = "SYMBOL",
                             keytype = "ENSEMBL")

rowData(se)$ID <- rownames(se)

se <- se[!is.na(rowData(se)$symbol)]

ddsSE <- se |> DESeqDataSet(design = ~ cell + dex)
keep <- ddsSE |> counts() |> apply(1, function(gene) { all(gene != 0) })
ddsSE <- ddsSE[keep, ]
dds <- ddsSE |> DESeq()

saveRDS(dds, "dds.rds")