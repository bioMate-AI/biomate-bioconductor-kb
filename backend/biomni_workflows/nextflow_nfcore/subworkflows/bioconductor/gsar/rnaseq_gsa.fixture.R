# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GSAR", "tweeDEseqCountData", "edgeR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GSAR)
library(tweeDEseqCountData)
library(edgeR)

data(pickrell)
data(annotEnsembl63)
data(genderGenes)

gender <- pickrell.eset$gender

allXgenes <- rownames(annotEnsembl63)[annotEnsembl63$Chr == "X"]
Xigenes <- allXgenes[!(allXgenes %in% XiEgenes)]

gene.indices <- which(!(is.na(annotEnsembl63$EntrezID) | is.na(annotEnsembl63$Length)))
PickrellDataSet <- exprs(pickrell.eset)
PickrellDataSet <- PickrellDataSet[gene.indices,]
genes.length <- annotEnsembl63$Length[gene.indices]

cpm.matrix <- cpm(PickrellDataSet)
cpm.means <- rowMeans(cpm.matrix)
cpm.filter <- which(cpm.means > 0.1)

PickrellDataSet <- PickrellDataSet[cpm.filter,]
genes.length <- genes.length[cpm.filter]

rpkm.set <- rpkm(PickrellDataSet, genes.length)
rpkm.set <- log2(1 + rpkm.set)

gene.space <- rownames(rpkm.set)
msYgenes <- msYgenes[msYgenes %in% gene.space]
XiEgenes <- XiEgenes[XiEgenes %in% gene.space]
Xigenes <- Xigenes[Xigenes %in% gene.space]
XYgenes <- c(msYgenes, XiEgenes)

group.label.pickrell <- (gender == "male") + 1

saveRDS(PickrellDataSet, "PickrellDataSet")
saveRDS(genes.length, "genes.length")
saveRDS(group.label.pickrell, "group.label.pickrell")
saveRDS(XYgenes, "XYgenes")