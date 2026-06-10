# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("affy", "hgu95av2.db", "genefilter", "estrogen", "limma", "categoryCompare", "GO.db", "KEGGREST")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("affy")
library("hgu95av2.db")
library("genefilter")
library("estrogen")
library("limma")
library("categoryCompare")
library("GO.db")
library("KEGGREST")

# Data loading and initial processing
datadir <- system.file("extdata", package = "estrogen")
pd <- read.AnnotatedDataFrame(file.path(datadir,"estrogen.txt"), header = TRUE, sep = "", row.names = 1)
filePaths <- file.path(datadir, rownames(pData(pd)))
a <- ReadAffy(filenames=filePaths, phenoData = pd, verbose = FALSE)
eData <- mas5(a)

# Processing for 10-hour samples
e10 <- eData[, eData$time.h == 10]
e10 <- nsFilter(e10, remove.dupEntrez=TRUE, var.filter=FALSE, feature.exclude="^AFFX")$eset
e10$estrogen <- factor(e10$estrogen)
d10 <- model.matrix(~0 + e10$estrogen)
colnames(d10) <- unique(e10$estrogen)
fit10 <- lmFit(e10, d10)
c10 <- makeContrasts(present - absent, levels=d10)
fit10_2 <- contrasts.fit(fit10, c10)
eB10 <- eBayes(fit10_2)
table10 <- topTable(eB10, number=nrow(e10), p.value=1, adjust.method="BH")
table10$Entrez <- unlist(mget(rownames(table10), hgu95av2ENTREZID, ifnotfound=NA))

# Processing for 48-hour samples
e48 <- eData[, eData$time.h == 48]
e48 <- nsFilter(e48, remove.dupEntrez=TRUE, var.filter=FALSE, feature.exclude="^AFFX" )$eset
e48$estrogen <- factor(e48$estrogen)
d48 <- model.matrix(~0 + e48$estrogen)
colnames(d48) <- unique(e48$estrogen)
fit48 <- lmFit(e48, d48)
c48 <- makeContrasts(present - absent, levels=d48)
fit48_2 <- contrasts.fit(fit48, c48)
eB48 <- eBayes(fit48_2)
table48 <- topTable(eB48, number=nrow(e48), p.value=1, adjust.method="BH")
table48$Entrez <- unlist(mget(rownames(table48), hgu95av2ENTREZID, ifnotfound=NA))

# Defining gUniverse
gUniverse <- unique(union(table10$Entrez, table48$Entrez))

# Create Gene List for categoryCompare
g10 <- unique(table10$Entrez[table10$adj.P.Val < 0.05])
g48 <- unique(table48$Entrez[table48$adj.P.Val < 0.05])

list10 <- list(genes=g10, universe=gUniverse, annotation='org.Hs.eg.db')
list48 <- list(genes=g48, universe=gUniverse, annotation='org.Hs.eg.db')
geneLists <- list(T10=list10, T48=list48)
geneLists <- new("ccGeneList", geneLists, ccType=c("BP","KEGG"))
fdr(geneLists) <- 0

# Save the geneLists object to gene_lists.RData
save(geneLists, file="gene_lists.RData")