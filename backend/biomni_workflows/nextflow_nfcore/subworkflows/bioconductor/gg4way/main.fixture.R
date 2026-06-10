# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("airway", "org.Hs.eg.db", "edgeR", "limma", "gg4way")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("airway")
library("org.Hs.eg.db")
library("edgeR")
library("limma")
library("gg4way")

data("airway")
se <- airway

rowData(se)$symbol <- mapIds(org.Hs.eg.db,
                             keys = rownames(se),
                             column = "SYMBOL",
                             keytype = "ENSEMBL")

rowData(se)$ID <- rownames(se)

se <- se[!is.na(rowData(se)$symbol)]

dge <- se |>
    SE2DGEList()

design <- model.matrix(~ 0 + cell + dex, data = dge$samples)
colnames(design) <- gsub("cell", "", colnames(design))

contr.matrix <- makeContrasts(N61311 - N052611,
                              N061011 - N052611,
                              levels = c("N052611", "N061011",
                                         "N080611", "N61311",
                                         "dexuntrt"))

keep <- filterByExpr(dge, design)
dge <- dge[keep, ]

efit <- dge |>
    calcNormFactors() |>
    voom(design) |>
    lmFit(design) |>
    contrasts.fit(contrasts = contr.matrix) |>
    eBayes()

saveRDS(efit, "efit.rds")